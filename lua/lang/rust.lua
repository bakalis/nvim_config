-- Rust: rust-analyzer (through rustaceanvim), debugging with codelldb, and run configurations.
-- Cargo commands and their switches (release, features, package) are in lua/lang/cargo.lua.
local platform = require("core.platform")
local cargo = require("lang.cargo")
local launch = require("lang.launch")

local M = {}

-- launch.json entries of these types are Rust ones: "lldb" is what VS Code's CodeLLDB writes
local launch_types = { codelldb = true, lldb = true }

local function find_root(bufnr)
	return cargo.root(bufnr) or vim.fn.getcwd()
end

M.find_root = find_root

---------------------------------------------------------------------------
-- rust-analyzer
---------------------------------------------------------------------------

--- The rust-analyzer of the project's toolchain (rustup, follows rust-toolchain.toml) so it always
--- matches the compiler, mason's when that toolchain has none (`rustup component add rust-analyzer`)
local function server_command()
	local cargo_home = vim.env.CARGO_HOME or platform.join(platform.home(), ".cargo")
	local proxy = platform.join(cargo_home, "bin", platform.exe_name("rust-analyzer"))
	local name = vim.api.nvim_buf_get_name(0)
	local dir = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
	if platform.has(proxy) and platform.system({ proxy, "--version" }, { cwd = dir }).code == 0 then
		return { proxy }
	end
	return { vim.fn.exepath("rust-analyzer") ~= "" and vim.fn.exepath("rust-analyzer") or "rust-analyzer" }
end

local settings = {
	["rust-analyzer"] = {
		cargo = {
			features = "all",
			buildScripts = { enable = true },
			-- its own target folder: checking on save never blocks (or is blocked by) a cargo build
			targetDir = true,
		},
		check = { command = "clippy" },
		checkOnSave = true,
		procMacro = { enable = true },
		imports = { granularity = { group = "module" }, prefix = "self" },
		completion = { postfix = { enable = true } },
		inlayHints = {
			chainingHints = { enable = true },
			closureReturnTypeHints = { enable = "with_block" },
			lifetimeElisionHints = { enable = "skip_trivial", useParameterNames = true },
			parameterHints = { enable = true },
			typeHints = { enable = true },
		},
		lens = { enable = true },
	},
}

---------------------------------------------------------------------------
-- Run configurations
---------------------------------------------------------------------------

--- What Cargo can start by itself: every binary and example, and every test target
local function discovered(root)
	local configs = {}
	for _, target in ipairs(cargo.targets(root, { "bin", "example", "test", "lib" })) do
		local suffix = target.name == target.package and "" or ("  (" .. target.package .. ")")
		local config = {
			type = "codelldb",
			request = "launch",
			args = {},
			cargoSwitches = true, -- built with the release/features switches of lua/lang/cargo.lua
		}
		if target.kind == "bin" or target.kind == "example" then
			config.name = (target.kind == "bin" and "Run " or "Example ") .. target.name .. suffix
			config.cargo = {
				args = { "build", "--package", target.package, "--" .. target.kind, target.name },
				filter = { name = target.name, kind = target.kind },
			}
			config.cwd = root
		else
			local unit = target.kind == "lib"
			config.name = (unit and "Unit tests " or "Test ") .. target.name .. suffix
			config.cargo = {
				args = vim.list_extend(
					{ "test", "--no-run", "--package", target.package },
					unit and { "--lib" } or { "--test", target.name }
				),
				filter = { name = target.name, kind = target.kind },
			}
			config.cwd = target.dir -- tests run in their package's folder, as with `cargo test`
		end
		table.insert(configs, config)
	end
	return configs
end

--- Saved configurations first, then the discovered ones
local function project_configs(root)
	return launch.merge(launch.saved(root, launch_types), discovered(root))
end

M.project_configs = project_configs

local function run_config(root, debug)
	local configs = project_configs(root)
	launch.pick(
		debug and configs or launch.launchable(configs),
		debug and "Debug configuration" or "Run configuration",
		function(config)
			launch.start(config, debug, "rust")
		end
	)
end

local function edit_configs(root)
	launch.edit(root, function()
		local entries = {}
		for _, target in ipairs(cargo.targets(root, { "bin" })) do
			table.insert(
				entries,
				string.format(
					[[
    {
      "type": "lldb",
      "request": "launch",
      "name": "Run %s",
      "cargo": {
        "args": ["build", "--package", "%s", "--bin", "%s"],
        "filter": { "name": "%s", "kind": "bin" }
      },
      "args": [],
      "env": {},
      "cwd": "${workspaceFolder}"
    }]],
					target.name,
					target.package,
					target.name,
					target.name
				)
			)
		end
		return entries
	end)
end

M.edit_configs = edit_configs

---------------------------------------------------------------------------
-- Debug adapter
---------------------------------------------------------------------------

--- Lets the debugger step into the standard library: its debug info points at /rustc/<commit>/...,
--- the sources are in the toolchain (rust-src component)
local source_maps = {}
local function std_source_map(cwd)
	if source_maps[cwd] == nil then
		local sysroot = vim.trim(platform.system({ "rustc", "--print", "sysroot" }, { cwd = cwd }).stdout)
		local commit = platform
			.system({ "rustc", "--version", "--verbose" }, { cwd = cwd }).stdout
			:match("commit%-hash: (%x+)")
		local sources = platform.join(sysroot, "lib", "rustlib", "src", "rust")
		source_maps[cwd] = (commit and vim.fn.isdirectory(sources) == 1) and { ["/rustc/" .. commit] = sources }
			or false
	end
	return source_maps[cwd] or nil
end

--- Does a built artifact match the "filter" of a configuration ({ name, kind })?
local function matches(artifact, filter)
	if not filter then
		return true
	end
	return (not filter.name or filter.name == artifact.name)
		and (not filter.kind or vim.list_contains(artifact.kinds, filter.kind))
end

--- A configuration with a "cargo" entry (CodeLLDB's launch.json format) names what to build instead of a
--- program: run that build, then debug the executable it produced.
local function build_program(config, on_config)
	local spec = config.cargo
	config.cargo = nil
	local args = vim.deepcopy(vim.islist(spec) and spec or spec.args or { "build" })
	local extra = { "--message-format=json" }
	if config.cargoSwitches then
		local switches = cargo.flags(cargo.root_of(config.cwd) or config.cwd)
		-- the package is already named by the configuration itself
		for index = #switches, 1, -1 do
			if switches[index] == "--package" then
				table.remove(switches, index + 1)
				table.remove(switches, index)
			end
		end
		vim.list_extend(extra, switches)
	end
	config.cargoSwitches = nil

	-- cargo's own options go before a `--` (what follows it is for the test binary)
	local command = { "cargo" }
	local separator = vim.fn.index(args, "--")
	vim.list_extend(command, separator >= 0 and vim.list_slice(args, 1, separator) or args)
	vim.list_extend(command, extra)
	if separator >= 0 then
		vim.list_extend(command, vim.list_slice(args, separator + 1))
	end
	local title = "cargo " .. table.concat(args, " ")
	vim.notify(title .. " ...")
	vim.cmd.wall({ mods = { silent = true, emsg_silent = true } })

	local ok, err = pcall(vim.system, command, { cwd = config.cwd, text = true, env = spec.env }, function(result)
		vim.schedule(function()
			local artifacts, rendered = {}, {}
			for line in (result.stdout or ""):gmatch("[^\n]+") do
				local decoded, message = pcall(vim.json.decode, line)
				if decoded and type(message) == "table" then
					if message.reason == "compiler-artifact" and type(message.executable) == "string" then
						table.insert(
							artifacts,
							{ path = message.executable, name = message.target.name, kinds = message.target.kind }
						)
					elseif message.reason == "compiler-message" and message.message.level == "error" then
						table.insert(rendered, message.message.rendered)
					end
				end
			end
			if result.code ~= 0 then
				local detail = #rendered > 0 and table.concat(rendered, "\n") or (result.stderr or "")
				vim.notify(title .. " failed, nothing to start:\n" .. detail, vim.log.levels.ERROR)
				return
			end

			local wanted = vim.tbl_filter(function(artifact)
				return matches(artifact, type(spec) == "table" and spec.filter or nil)
			end, artifacts)
			if #wanted == 0 then
				vim.notify(title .. " produced no executable for this configuration", vim.log.levels.ERROR)
			elseif #wanted == 1 then
				config.program = wanted[1].path
				on_config(config)
			else
				vim.ui.select(wanted, {
					prompt = "Executable",
					format_item = function(artifact)
						return artifact.name .. "  " .. vim.fn.fnamemodify(artifact.path, ":~:.")
					end,
				}, function(artifact)
					if artifact then
						config.program = artifact.path
						on_config(config)
					end
				end)
			end
		end)
	end)
	if not ok then
		vim.notify("Could not start cargo: " .. tostring(err), vim.log.levels.ERROR)
	end
end

--- Last step before a configuration reaches codelldb
local function enrich_config(config, on_config)
	config = vim.deepcopy(config)
	config.cwd = config.cwd or vim.fn.getcwd()
	config.sourceLanguages = config.sourceLanguages or { "rust" }
	config.sourceMap = config.sourceMap or std_source_map(config.cwd)
	if config.cargo then
		build_program(config, on_config)
	else
		config.cargoSwitches = nil
		on_config(config)
	end
end

local function adapter(callback)
	local command = vim.fn.exepath("codelldb")
	if command == "" then
		vim.notify("codelldb is not installed yet, see :Mason", vim.log.levels.ERROR)
		return
	end
	callback({
		type = "server",
		host = "127.0.0.1",
		port = "${port}",
		executable = { command = command, args = { "--port", "${port}" } },
		enrich_config = enrich_config,
		-- codelldb takes several seconds to come up the first time after an install or a reboot
		options = { max_retries = 60, initialize_timeout_sec = 20 },
	})
end

--- Called once from lua/plugins/debugger.lua
function M.setup_dap()
	local dap = require("dap")
	dap.adapters.codelldb = adapter
	dap.adapters.lldb = adapter -- the name VS Code's launch.json uses for CodeLLDB
	-- A plain run (noDebug) is still started by codelldb, which then rejects every breakpoint request
	-- ("Not supported in noDebug mode"), so none are sent
	dap.listeners.before.event_initialized["rust-plain-run"] = function(session)
		if session.config.noDebug and launch_types[session.config.type] then
			session.capabilities.exceptionBreakpointFilters = nil
			session.set_breakpoints = function(_, _, on_done)
				if on_done then
					on_done()
				end
			end
		end
	end
	-- everything of the project also shows up under <leader>dc; a launch.json in the working
	-- directory is already read by nvim-dap itself
	launch.add_provider("rust.project", "rust", function(bufnr)
		local root = find_root(bufnr)
		local configs = discovered(root)
		if not platform.same_path(root, vim.fn.getcwd()) then
			configs = launch.merge(launch.saved(root, launch_types), configs)
		end
		return configs
	end)
end

---------------------------------------------------------------------------
-- Keymaps and rustaceanvim
---------------------------------------------------------------------------

local function set_keymaps(bufnr)
	local map = function(mode, keys, func, desc)
		vim.keymap.set(mode, keys, func, { buffer = bufnr, desc = "Rust: " .. desc })
	end
	local function lsp(...)
		local args = { ... }
		return function()
			vim.cmd.RustLsp(#args == 1 and args[1] or args)
		end
	end

	map("n", "<leader>Rr", function()
		run_config(find_root(bufnr), false)
	end, "Run Configuration (no debugger)")
	map("n", "<leader>Rd", function()
		run_config(find_root(bufnr), true)
	end, "Debug Configuration")
	map("n", "<leader>Rl", function()
		require("dap").run_last()
	end, "Rerun Last")
	map("n", "<leader>Re", function()
		edit_configs(find_root(bufnr))
	end, "Edit Run Configurations")
	map("n", "<leader>Rn", lsp("debug"), "Debug Nearest Test / main")
	map("n", "<leader>Rt", lsp("debuggables"), "Debug a Test or Binary of this file")
	map("n", "<leader>Rm", lsp("expandMacro"), "Expand Macro")
	map("n", "<leader>Rx", lsp("explainError"), "Explain Error")
	map("n", "<leader>RD", lsp("renderDiagnostic"), "Render Diagnostic")
	map("n", "<leader>Ro", lsp("openDocs"), "Open docs.rs")
	map("n", "<leader>Rc", lsp("openCargo"), "Open Cargo.toml")
	map("n", "<leader>Rp", lsp("parentModule"), "Parent Module")
	map({ "n", "x" }, "<leader>Rj", lsp("joinLines"), "Join Lines")
	map("n", "<leader>RR", "<cmd>RustAnalyzer restart<cr>", "Restart rust-analyzer")
	map("n", "K", lsp("hover", "actions"), "Hover (with actions)")
end

--- vim.g.rustaceanvim, see lua/plugins/rust.lua
function M.config()
	return {
		tools = {
			enable_clippy = true,
		},
		server = {
			cmd = server_command,
			capabilities = require("blink.cmp").get_lsp_capabilities(),
			on_attach = function(_, bufnr)
				set_keymaps(bufnr)
			end,
			default_settings = settings,
		},
		dap = {
			-- no builds in the background just to list what could be debugged, see discovered()
			autoload_configurations = false,
			-- what `:RustLsp debug` and neotest's debug start with, the program and arguments are filled in
			configuration = { type = "codelldb", request = "launch", name = "Rust debug", stopOnEntry = false },
		},
	}
end

return M
