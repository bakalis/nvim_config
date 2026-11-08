local platform = require("core.platform")

local M = {}

-- jdtls itself needs Java 25+, projects can target any registered runtime
local function runner_jdk()
	return platform.runner_jdk(25)
end

local function runtimes(preferred)
	return platform.java_runtimes(preferred)
end

-- Maven (and anything else started from here) should use the JDK of the `java` on the PATH
M.ensure_java_home = platform.ensure_java_home

-- Multi-module projects need a single root, so a module's own pom.xml must not count
local function find_root(file)
	local root = vim.fs.root(file, { "mvnw", "gradlew", ".git" })
	if root then
		return root
	end
	local poms = vim.fs.find("pom.xml", { path = vim.fs.dirname(file), upward = true, limit = math.huge })
	return poms[#poms] and vim.fs.dirname(poms[#poms]) or vim.fs.dirname(file)
end

-- Eclipse formatter profile (the XML exported from Eclipse's Preferences > Formatter).
-- A project's own file wins, then a personal one in ~/.config/nvim/java/.
local formatter_names = {
	"eclipse-formatter.xml",
	"eclipse-java-formatter.xml",
	"formatter.xml",
	".settings/formatter.xml",
	"config/eclipse-formatter.xml",
	"eclipse-java-google-style.xml",
}

local function formatter_settings(root)
	local candidates = {}
	for _, name in ipairs(formatter_names) do
		table.insert(candidates, platform.join(root, name))
	end
	table.insert(candidates, platform.config("java", "eclipse-formatter.xml"))

	for _, path in ipairs(candidates) do
		if vim.fn.filereadable(path) == 1 then
			-- jdtls wants the profile name from inside the file, not the file name
			local profile, size, char
			for _, line in ipairs(vim.fn.readfile(path)) do
				profile = profile or line:match('<profile[^>]-name="([^"]+)"')
				size = size or line:match('tabulation%.size" value="(%d+)"')
				char = char or line:match('tabulation%.char" value="(%a+)"')
			end
			return { url = vim.uri_from_fname(path), profile = profile }, { size = tonumber(size), char = char }
		end
	end
end

local function bundles()
	local result = vim.fn.glob(platform.mason_package("java-debug-adapter", "extension", "server", "com.microsoft.java.debug.plugin-*.jar"), true, true)
	-- jdtls extensions the Spring Boot language server needs (bean and dependency hints)
	local ok, spring = pcall(function()
		return require("spring_boot").java_extensions()
	end)
	if ok and spring then
		vim.list_extend(result, spring)
	end
	local excluded = { "com.microsoft.java.test.runner-jar-with-dependencies.jar", "jacocoagent.jar" }
	for _, jar in ipairs(vim.fn.glob(platform.mason_package("java-test", "extension", "server", "*.jar"), true, true)) do
		if not vim.list_contains(excluded, vim.fn.fnamemodify(jar, ":t")) then
			table.insert(result, jar)
		end
	end
	return result
end

-- Run configurations, IntelliJ style. Saved ones live in <project>/.vscode/launch.json
-- (type "java", request "launch": mainClass, projectName, args, vmArgs, env, cwd),
-- discovered main classes are added to the list automatically.
local function launch_json(root)
	return platform.join(root, ".vscode", "launch.json")
end

local function launch_configs(root)
	local ok, configs = pcall(require("dap.ext.vscode").getconfigs, launch_json(root))
	return ok and configs or {}
end

-- Saved configurations first, then discovered main classes that no saved one covers
local function project_configs(root, callback)
	local configs = vim.deepcopy(launch_configs(root))
	local done = false
	local function finish(discovered)
		if done then
			return
		end
		done = true
		local covered = {}
		for _, config in ipairs(configs) do
			covered[config.mainClass or ""] = true
		end
		for _, config in ipairs(discovered or {}) do
			if not covered[config.mainClass] then
				table.insert(configs, config)
			end
		end
		callback(vim.tbl_filter(function(config)
			return config.request == "launch"
		end, configs))
	end
	-- jdtls may be missing or still importing, don't wait forever
	vim.defer_fn(finish, 4000)
	local ok = pcall(require("jdtls.dap").fetch_main_configs, nil, finish)
	if not ok then
		finish()
	end
end

local function pick_config(root, title, callback)
	project_configs(root, function(configs)
		if #configs == 0 then
			vim.notify("No Java run configurations found, create one with <leader>Je", vim.log.levels.WARN)
			return
		end
		vim.ui.select(configs, {
			prompt = title,
			format_item = function(config)
				return config.name
			end,
		}, function(config)
			if config then
				callback(config)
			end
		end)
	end)
end

-- Run without the debugger, output still goes to the terminal pane
local function run_config(root)
	pick_config(root, "Run configuration", function(config)
		config.noDebug = true
		require("dap").run(config)
	end)
end

local function edit_configs(root)
	local path = launch_json(root)
	if vim.fn.filereadable(path) == 0 then
		require("jdtls.dap").fetch_main_configs(nil, function(discovered)
			local entries = {}
			for _, config in ipairs(discovered or {}) do
				local class = config.mainClass:match("[^.]+$")
				table.insert(
					entries,
					string.format(
						[[
    {
      "type": "java",
      "request": "launch",
      "name": "Run %s",
      "mainClass": "%s",
      "projectName": "%s",
      "args": "",
      "vmArgs": "",
      "env": {},
      "cwd": "${workspaceFolder}"
    }]],
						class,
						config.mainClass,
						config.projectName or ""
					)
				)
			end
			vim.fn.mkdir(vim.fs.dirname(path), "p")
			vim.fn.writefile(
				vim.split(
					'{\n  "version": "0.2.0",\n  "configurations": [\n' .. table.concat(entries, ",\n") .. "\n  ]\n}",
					"\n"
				),
				path
			)
			vim.cmd.edit(path)
		end)
		return
	end
	vim.cmd.edit(path)
end

local function set_keymaps(bufnr, root)
	local jdtls = require("jdtls")
	local map = function(mode, keys, func, desc)
		vim.keymap.set(mode, keys, func, { buffer = bufnr, desc = "Java: " .. desc })
	end

	map("n", "<leader>Jo", jdtls.organize_imports, "Organize Imports")
	map({ "n", "x" }, "<leader>Jf", vim.lsp.buf.format, "Format")
	map("n", "<leader>Jv", jdtls.extract_variable, "Extract Variable")
	map("x", "<leader>Jv", function()
		jdtls.extract_variable(true)
	end, "Extract Variable")
	map("n", "<leader>JV", jdtls.extract_variable_all, "Extract Variable (all occurrences)")
	map("n", "<leader>Jc", jdtls.extract_constant, "Extract Constant")
	map("x", "<leader>Jc", function()
		jdtls.extract_constant(true)
	end, "Extract Constant")
	map("x", "<leader>Jm", function()
		jdtls.extract_method(true)
	end, "Extract Method")
	map("n", "<leader>Jd", function()
		require("dap").continue({ new = true })
	end, "Debug Configuration")
	map("n", "<leader>Jr", function()
		run_config(root)
	end, "Run Configuration (no debugger)")
	map("n", "<leader>Jl", function()
		require("dap").run_last()
	end, "Rerun Last")
	map("n", "<leader>Je", function()
		edit_configs(root)
	end, "Edit Run Configurations")
	map("n", "<leader>Jt", jdtls.test_class, "Debug Test Class")
	map("n", "<leader>Jn", jdtls.test_nearest_method, "Debug Nearest Test")
	map("n", "<leader>Jg", function()
		require("jdtls.tests").generate()
	end, "Generate Tests")
	map("n", "<leader>Js", function()
		require("jdtls.tests").goto_subjects()
	end, "Goto Test/Subject")
	map("n", "<leader>Jb", function()
		jdtls.compile("full")
	end, "Rebuild Workspace")
	map("n", "<leader>Ju", jdtls.update_projects_config, "Reload pom.xml")
	map("n", "<leader>Jh", "<cmd>JdtUpdateHotcode<cr>", "Hot Code Replace")
	map("n", "<leader>JR", "<cmd>JdtRestart<cr>", "Restart jdtls")
end

-- On the very first launch after installing jdtls the debug bundle doesn't register
-- its commands, and nvim-jdtls only sets up DAP if they exist. A restart fixes it.
local restarted_for_bundles = false
local function restart_if_debug_missing()
	local client = vim.lsp.get_clients({ name = "jdtls" })[1]
	local provider = client and client.server_capabilities.executeCommandProvider
	local commands = provider and provider.commands or {}
	if client and not restarted_for_bundles and not vim.list_contains(commands, "vscode.java.startDebugSession") then
		restarted_for_bundles = true
		vim.notify("jdtls: debug support not loaded on first launch, restarting")
		require("jdtls.setup").restart()
	end
end

-- neotest-java asks jdtls for the JDK of the directory a run starts in. In a multi-module
-- project "run all" starts in the aggregator pom, which jdtls doesn't import as a Java
-- project ("<name> does not exist"), so ask a child module instead.
function M.neotest_binaries()
	local cache = {}

	local function java_home(cwd)
		local dir = cwd:to_string()
		if cache[dir] then
			return cache[dir]
		end

		local nio = require("nio")
		local client = vim.lsp.get_clients({ name = "jdtls" })[1]
		local dirs = { dir }
		for _, pom in ipairs(vim.fs.find("pom.xml", { path = dir, limit = 20 })) do
			table.insert(dirs, vim.fs.dirname(pom))
		end
		for _, dir_candidate in ipairs(client and dirs or {}) do
			local future = nio.control.future()
			vim.schedule(function()
				client:request("workspace/executeCommand", {
					command = "java.project.getSettings",
					arguments = { vim.uri_from_fname(dir_candidate), { "org.eclipse.jdt.ls.core.vm.location" } },
				}, function(err, res)
					future.set(not err and res and res["org.eclipse.jdt.ls.core.vm.location"] or false)
				end)
			end)
			local home = future.wait()
			if home then
				cache[dir] = home
				return home
			end
		end

		M.ensure_java_home()
		cache[dir] = vim.env.JAVA_HOME
		return cache[dir]
	end

	local Path = require("neotest-java.model.path")
	return {
		java = function(cwd)
			return Path(platform.java_executable(java_home(cwd)))
		end,
		javap = function(cwd)
			return Path(platform.javap_executable(java_home(cwd)))
		end,
	}
end

local root_provider_added = false
local function add_root_launch_provider()
	if root_provider_added then
		return
	end
	root_provider_added = true
	require("dap").providers.configs["java.launch.json"] = function(bufnr)
		if vim.bo[bufnr].filetype ~= "java" then
			return {}
		end
		local root = find_root(vim.api.nvim_buf_get_name(bufnr))
		-- nvim-dap already reads <cwd>/.vscode/launch.json itself
		if platform.same_path(root, vim.fn.getcwd()) then
			return {}
		end
		return launch_configs(root)
	end
end

M.find_root = find_root
M.launch_configs = launch_configs
M.project_configs = project_configs
M.edit_configs = edit_configs

local attach_config_added = false
local function add_attach_config()
	if attach_config_added then
		return
	end
	attach_config_added = true
	-- Main classes are discovered by nvim-jdtls; this covers JVMs started elsewhere,
	-- such as `mvn -Dmaven.surefire.debug test` or `mvnDebug spring-boot:run`
	local dap = require("dap")
	dap.configurations.java = dap.configurations.java or {}
	table.insert(dap.configurations.java, {
		type = "java",
		request = "attach",
		name = "Attach to JVM",
		hostName = "127.0.0.1",
		port = function()
			return tonumber(vim.fn.input("Debug port: ", "5005"))
		end,
	})
end

function M.attach()
	local bufnr = vim.api.nvim_get_current_buf()
	local file = vim.api.nvim_buf_get_name(bufnr)
	-- jdt:// buffers (decompiled classes) are attached by nvim-jdtls itself
	if file == "" or file:match("^%a[%w+.-]*://") then
		return
	end

	local jdk = runner_jdk()
	if not jdk then
		vim.notify("jdtls needs JDK 25 or newer, try `brew install openjdk`", vim.log.levels.ERROR)
		return
	end
	if not platform.has("jdtls") then
		vim.notify("jdtls is not installed yet, see :Mason", vim.log.levels.WARN)
		return
	end
	add_attach_config()
	add_root_launch_provider()
	require("lang.spring").setup_dap() -- Run/Debug get the chosen Spring profiles

	local root = find_root(file)
	-- JAVA_HOME and the language server's default runtime follow the project's JDK (<leader>Jj)
	local project_jdk = require("lang.jdk").apply(root)
	local workspace = platform.jdtls_workspace(root)

	local jdtls = require("jdtls")
	local extended_capabilities = vim.deepcopy(jdtls.extendedClientCapabilities)
	extended_capabilities.resolveAdditionalTextEditsSupport = true

	local format_settings, indent = formatter_settings(root)

	jdtls.start_or_attach({
		cmd = {
			platform.command("jdtls"),
			"--java-executable=" .. platform.java_executable(jdk.path),
			"--jvm-arg=-javaagent:" .. platform.mason_package("jdtls", "lombok.jar"),
			"--jvm-arg=-Xmx2G",
			"-data",
			workspace,
		},
		root_dir = root,
		capabilities = require("blink.cmp").get_lsp_capabilities(),
		init_options = {
			bundles = bundles(),
			extendedClientCapabilities = extended_capabilities,
		},
		on_attach = function(_, buf)
			set_keymaps(buf, root)
			-- jdtls lets the editor's indent options override the profile in format requests
			vim.b[buf].java_format_on_save = format_settings ~= nil
			if indent and indent.size then
				vim.bo[buf].shiftwidth = indent.size
				vim.bo[buf].tabstop = indent.size
				vim.bo[buf].softtabstop = indent.size
				vim.bo[buf].expandtab = indent.char ~= "tab"
			end
		end,
		handlers = {
			["language/status"] = function(_, result)
				if result.type == "ServiceReady" then
					vim.schedule(restart_if_debug_missing)
				end
			end,
		},
		settings = {
			java = {
				configuration = {
					runtimes = runtimes(project_jdk and project_jdk.path),
					updateBuildConfiguration = "interactive",
				},
				format = { enabled = true, settings = format_settings },
				eclipse = { downloadSources = true },
				maven = { downloadSources = true },
				contentProvider = { preferred = "fernflower" },
				inlayHints = { parameterNames = { enabled = "all" } },
				references = { includeDecompiledSources = true },
				referencesCodeLens = { enabled = true },
				implementationsCodeLens = { enabled = true },
				signatureHelp = { enabled = true },
				sources = { organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 } },
				completion = {
					favoriteStaticMembers = {
						"org.junit.jupiter.api.Assertions.*",
						"org.assertj.core.api.Assertions.*",
						"org.mockito.Mockito.*",
						"org.mockito.ArgumentMatchers.*",
						"java.util.Objects.requireNonNull",
					},
				},
			},
		},
	}, {
		dap = { hotcodereplace = "auto" },
	})
end

return M
