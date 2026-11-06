local M = {}

local mason_packages = vim.fn.stdpath("data") .. "/mason/packages"

-- Every JDK on this machine as { major = 17, path = "..." }, newest first.
-- Homebrew's JDKs are keg-only, so java_home doesn't list them.
local jdks
local function installed_jdks()
	if jdks then
		return jdks
	end
	jdks = {}
	local result = vim.system({ "/usr/libexec/java_home", "-V" }, { text = true }):wait()
	for line in vim.gsplit(result.stderr or "", "\n") do
		local version, path = line:match("^%s*([%d%._]+).*%s(/.+/Contents/Home)$")
		if version then
			local first, second = version:match("^(%d+)%.?(%d*)")
			local major = tonumber(first) == 1 and tonumber(second) or tonumber(first)
			table.insert(jdks, { major = major, path = path })
		end
	end
	for _, path in ipairs(vim.fn.glob("/opt/homebrew/opt/openjdk*/libexec/openjdk.jdk/Contents/Home", true, true)) do
		local release = vim.fn.filereadable(path .. "/release") == 1 and vim.fn.readfile(path .. "/release") or {}
		for _, line in ipairs(release) do
			local major = line:match('^JAVA_VERSION="(%d+)')
			if major then
				table.insert(jdks, { major = tonumber(major), path = path })
			end
		end
	end
	table.sort(jdks, function(a, b)
		return a.major > b.major
	end)
	return jdks
end

-- jdtls itself needs Java 25+, projects can target any registered runtime
local function runner_jdk()
	local newest = installed_jdks()[1]
	return newest and newest.major >= 25 and newest or nil
end

local function runtimes()
	local seen, result = {}, {}
	for _, jdk in ipairs(installed_jdks()) do
		if not seen[jdk.major] then
			seen[jdk.major] = true
			local name = jdk.major == 8 and "JavaSE-1.8" or ("JavaSE-" .. jdk.major)
			table.insert(result, { name = name, path = jdk.path })
		end
	end
	return result
end

-- Homebrew's mvn runs on Homebrew's own JDK unless JAVA_HOME is set, so point it at
-- the same JDK as `java` on the PATH. An exported JAVA_HOME wins.
function M.ensure_java_home()
	if vim.env.JAVA_HOME then
		return
	end
	local result = vim.system({ "/usr/libexec/java_home" }, { text = true }):wait()
	if result.code == 0 then
		vim.env.JAVA_HOME = vim.trim(result.stdout)
	end
end

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
		table.insert(candidates, root .. "/" .. name)
	end
	table.insert(candidates, vim.fn.stdpath("config") .. "/java/eclipse-formatter.xml")

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
	local result = vim.fn.glob(mason_packages .. "/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar", true, true)
	-- jdtls extensions the Spring Boot language server needs (bean and dependency hints)
	local ok, spring = pcall(function()
		return require("spring_boot").java_extensions()
	end)
	if ok and spring then
		vim.list_extend(result, spring)
	end
	local excluded = { "com.microsoft.java.test.runner-jar-with-dependencies.jar", "jacocoagent.jar" }
	for _, jar in ipairs(vim.fn.glob(mason_packages .. "/java-test/extension/server/*.jar", true, true)) do
		if not vim.list_contains(excluded, vim.fn.fnamemodify(jar, ":t")) then
			table.insert(result, jar)
		end
	end
	return result
end

local function set_keymaps(bufnr)
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
	if vim.fn.executable("jdtls") == 0 then
		vim.notify("jdtls is not installed yet, see :Mason", vim.log.levels.WARN)
		return
	end
	M.ensure_java_home()
	add_attach_config()

	local root = find_root(file)
	local workspace = string.format(
		"%s/jdtls-workspaces/%s-%s",
		vim.fn.stdpath("data"),
		vim.fn.fnamemodify(root, ":t"),
		vim.fn.sha256(root):sub(1, 8)
	)

	local jdtls = require("jdtls")
	local extended_capabilities = vim.deepcopy(jdtls.extendedClientCapabilities)
	extended_capabilities.resolveAdditionalTextEditsSupport = true

	local format_settings, indent = formatter_settings(root)

	jdtls.start_or_attach({
		cmd = {
			"jdtls",
			"--java-executable=" .. jdk.path .. "/bin/java",
			"--jvm-arg=-javaagent:" .. mason_packages .. "/jdtls/lombok.jar",
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
			set_keymaps(buf)
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
					runtimes = runtimes(),
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
