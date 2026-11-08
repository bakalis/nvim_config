-- Everything that depends on the operating system lives in this file, the rest of the config
-- calls these helpers the same way on macOS, Linux and Windows:
--   * paths: join/normalize, standard folders, the home directory from $HOME or %USERPROFILE%
--   * executables: .exe/.cmd suffixes, python virtualenv layouts, locating client tools
--   * subprocesses: list-form commands only, never a shell string
--   * build steps and options that differ per system
-- Locations are derived from environment variables ($HOME, %ProgramFiles%, ...) wherever possible.
local M = {}

local sysname = vim.uv.os_uname().sysname

M.is_windows = sysname == "Windows_NT" or sysname:find("^MINGW") ~= nil or sysname:find("^MSYS") ~= nil
M.is_macos = sysname == "Darwin"
M.is_linux = sysname == "Linux"
M.name = M.is_windows and "windows" or (M.is_macos and "macos" or "linux")

--- separator between the entries of $PATH
M.path_list_separator = M.is_windows and ";" or ":"

---------------------------------------------------------------------------
-- Paths
---------------------------------------------------------------------------

--- $HOME, or %USERPROFILE% on Windows
function M.home()
	return vim.env.HOME or vim.env.USERPROFILE or vim.uv.os_homedir()
end

--- Join path parts with the right separator
function M.join(...)
	return vim.fs.joinpath(...)
end

--- Expand ~ and $VARIABLES and use forward slashes everywhere (Windows included)
function M.normalize(path)
	if M.is_windows then
		path = path:gsub("\\", "/")
	end
	return vim.fs.normalize(path)
end

--- Remove trailing separators, git hands directories over with one
function M.strip_trailing_separator(path)
	local stripped = path:gsub("[/\\]+$", "")
	return stripped ~= "" and stripped or path
end

--- Compare two paths, ignoring separator style (and case on Windows)
function M.same_path(a, b)
	a, b = M.strip_trailing_separator(M.normalize(a)), M.strip_trailing_separator(M.normalize(b))
	if M.is_windows then
		a, b = a:lower(), b:lower()
	end
	return a == b
end

--- Path inside Neovim's data directory (plugins, mason, saved queries, ...)
function M.data(...)
	return M.join(vim.fn.stdpath("data"), ...)
end

--- Path inside this configuration
function M.config(...)
	return M.join(vim.fn.stdpath("config"), ...)
end

--- Path inside a mason package (mason/packages/<name>/...)
function M.mason_package(...)
	return M.data("mason", "packages", ...)
end

---------------------------------------------------------------------------
-- Executables and subprocesses
---------------------------------------------------------------------------

--- Is this command (or path) runnable? Handles .exe/.cmd through PATHEXT on Windows
function M.has(command)
	return vim.fn.executable(command) == 1
end

--- The shell the terminal toggle starts, as a command list: PowerShell on Windows (pwsh when installed),
--- $SHELL elsewhere
function M.shell()
	if M.is_windows then
		for _, name in ipairs({ "pwsh", "powershell" }) do
			if M.has(name) then
				return { name }
			end
		end
		return { vim.env.COMSPEC or "cmd.exe" }
	end
	local shell = vim.env.SHELL
	if shell and shell ~= "" and M.has(shell) then
		return { shell }
	end
	return { vim.o.shell }
end

--- Whether a process name is an interactive shell (zsh, bash, fish, PowerShell, cmd, ...)
function M.is_shell(name)
	name = (name or ""):lower():gsub("%.exe$", ""):gsub("^%-", "") -- login shells show up as "-zsh"
	for _, shell in ipairs({ "zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "elvish", "pwsh", "powershell", "cmd" }) do
		if name == shell then
			return true
		end
	end
	return false
end

--- Name of a compiled program: `app` becomes `app.exe` on Windows
function M.exe_name(name)
	if M.is_windows and not name:lower():match("%.exe$") then
		return name .. ".exe"
	end
	return name
end

--- Run a command given as a list, no shell involved. Never throws: a missing program gives code 127.
--- Returns { code, stdout, stderr }.
function M.system(command, opts)
	local ok, result = pcall(function()
		return vim.system(command, vim.tbl_extend("force", { text = true }, opts or {})):wait()
	end)
	if not ok then
		return { code = 127, stdout = "", stderr = tostring(result) }
	end
	return { code = result.code, stdout = result.stdout or "", stderr = result.stderr or "" }
end

--- Put a directory in front of $PATH for this Neovim only, if it exists and is not there yet
function M.prepend_path(dir)
	if not dir or dir == "" or vim.fn.isdirectory(dir) == 0 then
		return false
	end
	local current = vim.env.PATH or ""
	for _, entry in ipairs(vim.split(current, M.path_list_separator, { plain = true })) do
		if entry ~= "" and M.same_path(entry, dir) then
			return false
		end
	end
	vim.env.PATH = dir .. M.path_list_separator .. current
	return true
end

---------------------------------------------------------------------------
-- Python
---------------------------------------------------------------------------

--- Interpreter of a virtualenv folder: bin/python, or Scripts/python.exe on Windows
function M.venv_python(dir)
	local python = M.is_windows and M.join(dir, "Scripts", "python.exe") or M.join(dir, "bin", "python")
	return M.has(python) and python or nil
end

--- Interpreter of the project's virtualenv: the active one ($VIRTUAL_ENV), else .venv, venv or env
function M.project_python(root)
	local active = vim.env.VIRTUAL_ENV
	if active and active ~= "" and vim.fn.isdirectory(active) == 1 then
		local python = M.venv_python(active)
		if python then
			return python
		end
	end
	for _, name in ipairs({ ".venv", "venv", "env" }) do
		local python = M.venv_python(M.join(root or vim.fn.getcwd(), name))
		if python then
			return python
		end
	end
end

--- A python on the PATH. `python3` is a Microsoft Store stub on Windows, so it is tried last there
function M.system_python()
	for _, name in ipairs(M.is_windows and { "python", "py", "python3" } or { "python3", "python" }) do
		if M.has(name) then
			return name
		end
	end
end

--- Project virtualenv if there is one, else whatever python is on the PATH
function M.python(root)
	return M.project_python(root) or M.system_python()
end

---------------------------------------------------------------------------
-- Tools that are installed but not on the PATH
---------------------------------------------------------------------------

--- Homebrew prefixes on this machine: whatever `brew --prefix` says, then the Apple silicon and Intel defaults
function M.homebrew_prefixes()
	local prefixes = {}
	local brew = M.has("brew") and vim.trim(M.system({ "brew", "--prefix" }).stdout) or ""
	if brew ~= "" then
		table.insert(prefixes, brew)
	end
	vim.list_extend(prefixes, { "/opt/homebrew", "/usr/local" })
	return prefixes
end

--- Make `psql` and `mysql` findable: Homebrew keeps them out of the PATH (keg-only), Debian and
--- Red Hat put them in versioned folders, the Windows installers in Program Files.
function M.ensure_database_clients()
	if M.has("psql") and M.has("mysql") then
		return
	end

	local directories = {}
	if M.is_macos then
		for _, prefix in ipairs(M.homebrew_prefixes()) do
			for _, formula in ipairs({ "libpq", "mysql-client" }) do
				table.insert(directories, M.join(prefix, "opt", formula, "bin"))
			end
		end
	elseif M.is_linux then
		vim.list_extend(directories, vim.fn.glob("/usr/lib/postgresql/*/bin", true, true)) -- Debian, Ubuntu
		vim.list_extend(directories, vim.fn.glob("/usr/pgsql-*/bin", true, true)) -- Red Hat, Fedora
	else
		for _, variable in ipairs({ "ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA" }) do
			local base = vim.env[variable]
			if base and base ~= "" then
				vim.list_extend(directories, vim.fn.glob(M.join(base, "PostgreSQL", "*", "bin"), true, true))
				vim.list_extend(directories, vim.fn.glob(M.join(base, "MySQL", "MySQL Server *", "bin"), true, true))
			end
		end
	end

	for _, directory in ipairs(directories) do
		M.prepend_path(directory)
	end
end

---------------------------------------------------------------------------
-- Build steps and options
---------------------------------------------------------------------------

--- Build command for telescope-fzf-native: make where there is one, cmake on Windows, else none
function M.fzf_native_build()
	if M.has("make") then
		return "make"
	end
	if M.is_windows and M.has("cmake") then
		return "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release && cmake --install build --prefix build"
	end
	return nil
end

--- Use the system clipboard for yank and paste, but only when Neovim found a provider for it
--- (pbcopy, xclip, wl-clipboard, win32yank, ...), otherwise every yank would print an error
function M.clipboard()
	return vim.fn.has("clipboard") == 1 and "unnamedplus" or ""
end

--- Keep Vim's own plugin folder out of the runtimepath when Vim is installed next to Neovim
function M.isolate_from_vim()
	if not M.is_windows then
		vim.opt.runtimepath:remove("/usr/share/vim/vimfiles")
	end
end

--- lazygit settings that are kept in this repository (lazygit/config.yml), so every machine uses the
--- same ones instead of the per-OS default location
function M.use_lazygit_config()
	local file = M.config("lazygit", "config.yml")
	if vim.uv.fs_stat(file) then
		vim.env.LG_CONFIG_FILE = file
	end
end

---------------------------------------------------------------------------
-- Java (used by the Java setup only)
---------------------------------------------------------------------------

--- Full path to a program, so .cmd/.bat shims (mvn.cmd, jdtls.cmd, ...) also start on Windows
function M.command(name)
	local path = vim.fn.exepath(name)
	return path ~= "" and path or name
end

function M.java_executable(home)
	return M.join(home, "bin", M.exe_name("java"))
end

function M.javap_executable(home)
	return M.join(home, "bin", M.exe_name("javap"))
end

--- What a JDK says about itself: { major = 17, version = "17.0.13", vendor = "Corretto" }.
--- Read from its `release` file; JDK 8 builds often have none, so those are asked with `java -version`.
local function jdk_info(home)
	local function major_of(version)
		return tonumber(version:match("^1%.(%d+)") or version:match("^(%d+)"))
	end
	local release = M.join(home, "release")
	if vim.fn.filereadable(release) == 1 then
		local info = {}
		for _, line in ipairs(vim.fn.readfile(release)) do
			local key, value = line:match('^([%w_]+)="(.*)"$')
			if key == "JAVA_VERSION" then
				info.version = value
			elseif key == "IMPLEMENTOR_VERSION" then
				info.vendor = value:match("^([%a][%w ]-)%-%d") or value:match("^(%a[%a ]*)")
			elseif key == "IMPLEMENTOR" and not info.vendor then
				info.vendor = value
			end
		end
		if info.version then
			info.major = major_of(info.version)
			return info
		end
	end
	local java = M.java_executable(home)
	if M.has(java) then
		local output = M.system({ java, "-version" }).stderr
		local version = output:match('version "([^"]+)"')
		if version then
			return { major = major_of(version), version = version, vendor = output:match("Runtime Environment (%a+)") }
		end
	end
end

local function jdk_major(home)
	local info = jdk_info(home)
	return info and info.major
end

--- Persistent choices (project -> JDK, extra JDK folders) in one JSON file in the data directory,
--- kept out of the projects themselves like IntelliJ's .idea is
local function store_file()
	return M.data("java-projects.json")
end

local function read_store()
	local store = {}
	if vim.fn.filereadable(store_file()) == 1 then
		local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(store_file()), "\n"))
		if ok and type(decoded) == "table" then
			store = decoded
		end
	end
	store.projects = type(store.projects) == "table" and store.projects or {}
	store.custom_jdks = type(store.custom_jdks) == "table" and store.custom_jdks or {}
	return store
end

local function write_store(store)
	vim.fn.mkdir(vim.fs.dirname(store_file()), "p")
	vim.fn.writefile({ vim.json.encode(store) }, store_file())
end

local function glob_into(patterns, list)
	for _, pattern in ipairs(patterns) do
		vim.list_extend(list, vim.fn.glob(pattern, true, true))
	end
end

--- Folders that may be a JDK home, per system. Version managers use the same layout everywhere.
local function jdk_home_candidates()
	local homes = {}
	local home = M.home()

	-- JAVA_HOME, JAVA_HOME_17_X64 and friends
	for name, value in pairs(vim.fn.environ()) do
		if name:upper():match("^JAVA_HOME") and value ~= "" then
			table.insert(homes, value)
		end
	end

	if M.is_macos then
		-- /usr/libexec/java_home knows the system and per-user JDKs, Homebrew's are keg-only
		for line in vim.gsplit(M.system({ "/usr/libexec/java_home", "-V" }).stderr, "\n") do
			local path = line:match("%s(/.+/Contents/Home)$")
			if path then
				table.insert(homes, path)
			end
		end
		for _, prefix in ipairs(M.homebrew_prefixes()) do
			glob_into({ M.join(prefix, "opt", "openjdk*", "libexec", "openjdk.jdk", "Contents", "Home") }, homes)
		end
		glob_into({
			M.join(home, "Library", "Java", "JavaVirtualMachines", "*", "Contents", "Home"),
			"/Library/Java/JavaVirtualMachines/*/Contents/Home",
		}, homes)
	elseif M.is_linux then
		glob_into({ "/usr/lib/jvm/*", "/usr/lib64/jvm/*", "/usr/java/*", "/opt/java/*", "/opt/jdk*" }, homes)
	else
		for _, variable in ipairs({ "ProgramFiles", "ProgramW6432", "ProgramFiles(x86)" }) do
			local base = vim.env[variable]
			if base and base ~= "" then
				for _, vendor in ipairs({ "Java", "Eclipse Adoptium", "Eclipse Foundation", "Microsoft", "Amazon Corretto", "Zulu", "BellSoft", "Semeru", "OpenJDK" }) do
					glob_into({ M.join(base, vendor, "*") }, homes)
				end
			end
		end
		glob_into({ M.join(vim.env.SCOOP or M.join(home, "scoop"), "apps", "*jdk*", "current") }, homes)
	end

	vim.list_extend(homes, read_store().custom_jdks)

	glob_into({
		M.join(vim.env.SDKMAN_DIR or M.join(home, ".sdkman"), "candidates", "java", "*"),
		M.join(home, ".jdks", "*"), -- JDKs downloaded by IntelliJ
		M.join(home, ".asdf", "installs", "java", "*"),
		M.join(home, ".local", "share", "mise", "installs", "java", "*"),
	}, homes)

	return homes
end

local jdk_cache

--- Every JDK on this machine as { major = 17, path = "..." }, newest first
function M.jdks()
	if jdk_cache then
		return jdk_cache
	end
	local seen, result = {}, {}
	for _, home in ipairs(jdk_home_candidates()) do
		local real = vim.uv.fs_realpath(home) or home
		local info = not seen[real] and M.has(M.java_executable(home)) and jdk_info(home) or nil
		if info and info.major then
			seen[real] = true
			table.insert(result, { major = info.major, version = info.version, vendor = info.vendor, path = home })
		end
	end
	table.sort(result, function(a, b)
		if a.major ~= b.major then
			return a.major > b.major
		end
		return a.path < b.path
	end)
	jdk_cache = result
	return result
end

--- The newest JDK that is at least `minimum`, or nil
function M.runner_jdk(minimum)
	local newest = M.jdks()[1]
	return newest and newest.major >= minimum and newest or nil
end

--- JDKs in the form the Java language server wants: { name = "JavaSE-17", path = "..." }, one per
--- major version. For the major of `preferred` (the project's JDK) that JDK is the one listed, and it
--- is marked as the default runtime.
function M.java_runtimes(preferred)
	local result, index = {}, {}
	local function add(jdk, is_preferred)
		local entry = { name = jdk.major == 8 and "JavaSE-1.8" or ("JavaSE-" .. jdk.major), path = jdk.path }
		if is_preferred then
			entry.default = true
		end
		if index[jdk.major] then
			if is_preferred then
				result[index[jdk.major]] = entry
			end
		else
			table.insert(result, entry)
			index[jdk.major] = #result
		end
	end
	for _, jdk in ipairs(M.jdks()) do
		add(jdk, preferred ~= nil and M.same_path(jdk.path, preferred))
	end
	return result
end

--- Make sure JAVA_HOME is set for this Neovim, so Maven and friends use the JDK of the `java` on the
--- PATH and not their own (Homebrew's mvn would run on Homebrew's JDK). An exported JAVA_HOME wins.
function M.ensure_java_home()
	if vim.env.JAVA_HOME and vim.env.JAVA_HOME ~= "" then
		return
	end
	local home
	if M.is_macos then
		local result = M.system({ "/usr/libexec/java_home" })
		home = result.code == 0 and vim.trim(result.stdout) or nil
	end
	if not home then
		-- <home>/bin/java, resolving symlinks such as /usr/bin/java -> /usr/lib/jvm/<jdk>/bin/java
		local java = vim.fn.exepath("java")
		if java ~= "" then
			home = vim.fs.dirname(vim.fs.dirname(vim.uv.fs_realpath(java) or java))
		end
	end
	if not (home and jdk_major(home)) and M.jdks()[1] then
		home = M.jdks()[1].path
	end
	if home and jdk_major(home) then
		vim.env.JAVA_HOME = home
	end
end

--- Java version a project asks for, read from its files, or nil:
--- { major = 17, source = ".sdkmanrc" }. Order: .sdkmanrc, .tool-versions, .java-version, then pom.xml.
function M.declared_java(root)
	local function major_of(text)
		local version = text and text:match("%d[%d%.]*")
		return version and tonumber(version:match("^1%.(%d+)") or version:match("^(%d+)")) or nil
	end
	local function lines_of(name)
		local file = M.join(root, name)
		return vim.fn.filereadable(file) == 1 and vim.fn.readfile(file) or {}
	end

	for _, line in ipairs(lines_of(".sdkmanrc")) do
		local major = major_of(line:match("^%s*java%s*=%s*(%S+)"))
		if major then
			return { major = major, source = ".sdkmanrc" }
		end
	end
	for _, line in ipairs(lines_of(".tool-versions")) do
		local major = major_of(line:match("^%s*java%s+(%S+)"))
		if major then
			return { major = major, source = ".tool-versions" }
		end
	end
	local jenv = lines_of(".java-version")[1]
	if major_of(jenv) then
		return { major = major_of(jenv), source = ".java-version" }
	end

	local pom = table.concat(lines_of("pom.xml"), "\n")
	for _, tag in ipairs({ "maven.compiler.release", "java.version", "release", "maven.compiler.source", "maven.compiler.target" }) do
		local value = pom:match("<" .. tag:gsub("%.", "%%.") .. ">%s*([^<%s]+)%s*</")
		if value and not value:find("${", 1, true) and major_of(value) then
			return { major = major_of(value), source = "pom.xml (" .. tag .. ")" }
		end
	end
end

--- One remembered setting of a project (the JDK, the Spring profiles, ...), or nil
function M.project_option(root, name)
	local entry = read_store().projects[M.normalize(root)]
	return entry and entry[name]
end

--- Remember a setting of a project, nil forgets it
function M.set_project_option(root, name, value)
	local store = read_store()
	local key = M.normalize(root)
	local entry = store.projects[key] or {}
	entry[name] = value
	store.projects[key] = next(entry) ~= nil and entry or nil
	write_store(store)
end

--- The JDK a project should use, and why: your explicit choice, else the version its files declare
--- (the closest installed one, an exact match first), else nil and the machine default applies.
function M.project_jdk(root)
	local chosen = M.project_option(root, "jdk")
	if chosen then
		for _, jdk in ipairs(M.jdks()) do
			if M.same_path(jdk.path, chosen) then
				return jdk, "chosen"
			end
		end
	end
	local declared = M.declared_java(root)
	if declared then
		local jdks = M.jdks() -- newest first
		for _, jdk in ipairs(jdks) do
			if jdk.major == declared.major then
				return jdk, declared.source
			end
		end
		for index = #jdks, 1, -1 do
			if jdks[index].major > declared.major then
				return jdks[index], declared.source .. ", but no JDK " .. declared.major .. " is installed"
			end
		end
	end
end

--- Remember your JDK for a project, or forget it with nil to follow the project's own files again
function M.set_project_jdk(root, path)
	M.set_project_option(root, "jdk", path)
end

--- Register a JDK folder that is not found automatically. Returns the JDK, or nil and the reason.
function M.add_custom_jdk(path)
	path = M.strip_trailing_separator(M.normalize(path))
	if not M.has(M.java_executable(path)) then
		return nil, "no bin/" .. M.exe_name("java") .. " in " .. path
	end
	if not jdk_major(path) then
		return nil, "could not read the Java version of " .. path
	end
	local store = read_store()
	if not vim.tbl_contains(store.custom_jdks, path) then
		table.insert(store.custom_jdks, path)
		write_store(store)
	end
	jdk_cache = nil
	for _, jdk in ipairs(M.jdks()) do
		if M.same_path(jdk.path, path) then
			return jdk
		end
	end
end

local exported_java_home = vim.env.JAVA_HOME -- what the shell exported, before anything below changed it

--- Point JAVA_HOME (for Maven and every command started from here) at the JDK of this project. Without
--- a project JDK it falls back to the exported JAVA_HOME, then to the machine default.
function M.use_project_jdk(root)
	local jdk, source = M.project_jdk(root)
	if jdk then
		vim.env.JAVA_HOME = jdk.path
		return jdk, source
	end
	vim.env.JAVA_HOME = exported_java_home
	M.ensure_java_home()
end

--- Maven: the project's wrapper (mvnw, or mvnw.cmd on Windows), else mvn from the PATH
function M.maven_executable(root)
	local wrapper = M.join(root or vim.fn.getcwd(), M.is_windows and "mvnw.cmd" or "mvnw")
	return M.has(wrapper) and wrapper or M.command("mvn")
end

--- Data folder of the Java language server for one project. Short names, Windows has a path length limit.
function M.jdtls_workspace(root)
	local name = vim.fn.fnamemodify(root, ":t"):gsub("[^%w._-]", "_"):sub(1, 24)
	return M.data("jdtls-workspaces", name .. "-" .. vim.fn.sha256(M.normalize(root)):sub(1, 8))
end

return M
