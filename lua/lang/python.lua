-- Python: debugging with debugpy and run configurations. The language server is set up in
-- lua/plugins/lsp.lua, tests in lua/plugins/neotest.lua.
local platform = require("core.platform")
local launch = require("lang.launch")

local M = {}

-- "python" is the older name of the "debugpy" type in launch.json
local launch_types = { debugpy = true, python = true }

local function find_root(bufnr)
	local markers =
		{ "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "manage.py", ".venv", "venv", ".git" }
	local name = vim.api.nvim_buf_get_name(bufnr or 0)
	return (name ~= "" and vim.fs.root(name, markers)) or vim.fn.getcwd()
end

M.find_root = find_root

--- Arguments typed at a prompt, the last answer is offered again
local last_arguments = ""
local function ask_arguments()
	last_arguments = vim.fn.input("Arguments: ", last_arguments)
	return last_arguments == "" and {} or vim.split(last_arguments, "%s+", { trimempty = true })
end

---------------------------------------------------------------------------
-- Run configurations
---------------------------------------------------------------------------

local last_remote = { host = "127.0.0.1", port = 5678 }

--- What can be started without a launch.json: the current file, its tests, the project's web app,
--- and a debugpy that is already listening somewhere
local function discovered(root)
	local function config(name, fields)
		return vim.tbl_extend("force", { type = "debugpy", request = "launch", name = name, cwd = root }, fields)
	end

	local configs = {
		config("Current file", { program = "${file}" }),
		config("Current file (with arguments)", { program = "${file}", args = ask_arguments }),
		config("Module (python -m)", {
			module = function()
				local name = vim.trim(vim.fn.input("Module: "))
				return name ~= "" and name or require("dap").ABORT
			end,
			args = ask_arguments,
		}),
		config("pytest: current file", { module = "pytest", args = { "${file}", "-v" } }),
		config("pytest: all", { module = "pytest", args = { "-v" } }),
	}

	if vim.fn.filereadable(platform.join(root, "manage.py")) == 1 then
		table.insert(
			configs,
			config(
				"Django",
				{ program = platform.join(root, "manage.py"), args = { "runserver", "--noreload" }, django = true }
			)
		)
	end
	for _, app in ipairs({ "app.py", "wsgi.py" }) do
		if vim.fn.filereadable(platform.join(root, app)) == 1 then
			table.insert(
				configs,
				config("Flask (" .. app .. ")", {
					module = "flask",
					env = { FLASK_APP = app, FLASK_DEBUG = "1" },
					args = { "run", "--no-debugger", "--no-reload" },
					jinja = true,
				})
			)
		end
	end

	-- A program started with `python -m debugpy --listen 5678 --wait-for-client app.py`
	table.insert(configs, {
		type = "debugpy",
		request = "attach",
		name = "Attach to debugpy",
		connect = {
			host = "127.0.0.1",
			port = function()
				return tonumber(vim.fn.input("Debug port: ", "5678")) or require("dap").ABORT
			end,
		},
	})
	-- On another machine, or behind a tunnel or container: asks for host and port. The last answer is the default.
	table.insert(configs, {
		type = "debugpy",
		request = "attach",
		name = "Attach to remote debugpy",
		connect = {
			host = function()
				local host = vim.trim(vim.fn.input("Remote host: ", last_remote.host))
				if host ~= "" then
					last_remote.host = host
				end
				return last_remote.host
			end,
			port = function()
				local port = tonumber(vim.fn.input("Remote debug port: ", tostring(last_remote.port)))
				if port then
					last_remote.port = port
				end
				return last_remote.port
			end,
		},
	})
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
			launch.start(config, debug, "python")
		end
	)
end

local function edit_configs(root)
	launch.edit(root, function()
		return {
			[[
    {
      "type": "debugpy",
      "request": "launch",
      "name": "Run main.py",
      "program": "${workspaceFolder}/main.py",
      "args": [],
      "env": {},
      "cwd": "${workspaceFolder}",
      "justMyCode": true
    }]],
			[[
    {
      "type": "debugpy",
      "request": "launch",
      "name": "Run module",
      "module": "package.module",
      "args": [],
      "env": {},
      "cwd": "${workspaceFolder}"
    }]],
		}
	end)
end

M.edit_configs = edit_configs

---------------------------------------------------------------------------
-- Debug adapter
---------------------------------------------------------------------------

--- Last step before a configuration reaches debugpy: the project's virtualenv runs the program
--- (unless the configuration names an interpreter), and its output goes to the terminal pane
local function enrich_config(config, on_config)
	config = vim.deepcopy(config)
	if config.request == "launch" then
		config.cwd = config.cwd or vim.fn.getcwd()
		config.console = config.console or "integratedTerminal"
		if not config.python and not config.pythonPath then
			config.python = platform.project_python(config.cwd) or platform.python(find_root(0))
		end
	end
	on_config(config)
end

local function adapter(callback, config)
	if config.request == "attach" then
		local connect = config.connect or config
		local port = tonumber(connect.port)
		if not port then
			vim.notify("debugpy: the configuration needs a port to attach to", vim.log.levels.ERROR)
			return
		end
		callback({
			type = "server",
			host = connect.host or "127.0.0.1",
			port = port,
			enrich_config = enrich_config,
			options = { source_filetype = "python" },
		})
		return
	end
	local command = vim.fn.exepath("debugpy-adapter")
	if command == "" then
		vim.notify("debugpy is not installed yet, see :Mason", vim.log.levels.ERROR)
		return
	end
	callback({
		type = "executable",
		command = command,
		enrich_config = enrich_config,
		options = { source_filetype = "python" },
	})
end

--- Called once from lua/plugins/debugger.lua
function M.setup_dap()
	local dap = require("dap")
	dap.adapters.debugpy = adapter
	dap.adapters.python = adapter
	-- everything of the project also shows up under <leader>dc; a launch.json in the working
	-- directory is already read by nvim-dap itself
	launch.add_provider("python.project", "python", function(bufnr)
		local root = find_root(bufnr)
		local configs = discovered(root)
		if not platform.same_path(root, vim.fn.getcwd()) then
			configs = launch.merge(launch.saved(root, launch_types), configs)
		end
		return configs
	end)
end

---------------------------------------------------------------------------
-- Keymaps
---------------------------------------------------------------------------

--- Runs for every Python buffer (ftplugin/python.lua)
function M.attach()
	local bufnr = vim.api.nvim_get_current_buf()
	local map = function(keys, func, desc)
		vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "Python: " .. desc })
	end

	map("<leader>Pr", function()
		run_config(find_root(bufnr), false)
	end, "Run Configuration (no debugger)")
	map("<leader>Pd", function()
		run_config(find_root(bufnr), true)
	end, "Debug Configuration")
	map("<leader>Pl", function()
		require("dap").run_last()
	end, "Rerun Last")
	map("<leader>Pe", function()
		edit_configs(find_root(bufnr))
	end, "Edit Run Configurations")
	map("<leader>Pn", function()
		require("neotest").run.run({ strategy = "dap" })
	end, "Debug Nearest Test")
	map("<leader>Pt", function()
		require("neotest").run.run({ vim.fn.expand("%"), strategy = "dap" })
	end, "Debug Test File")
	map("<leader>Pi", function()
		local root = find_root(bufnr)
		vim.notify("Python: " .. (platform.python(root) or "no interpreter found") .. "\nProject: " .. root)
	end, "Show Interpreter")
end

return M
