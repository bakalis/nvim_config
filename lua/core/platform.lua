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

return M
