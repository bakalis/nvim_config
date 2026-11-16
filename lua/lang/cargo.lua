-- Cargo from inside Neovim: build, run, check, clippy, test and doc in an output pane at the bottom,
-- with three switches that apply to all of them (and to Run/Debug in lua/lang/rust.lua):
--   release profile     --release
--   features            --features a,b  or  --all-features
--   workspace package   --package name
-- build, check and clippy also fill the quickfix list with the compiler's errors and warnings.
local platform = require("core.platform")

local M = {}

local state = {
	release = false,
	features = {}, -- root -> { all = boolean, names = { name = true } }
	package = {}, -- root -> package name
}

---------------------------------------------------------------------------
-- The project
---------------------------------------------------------------------------

local roots = {} -- directory -> workspace root

--- The workspace root (the folder of the outermost Cargo.toml) a directory belongs to, nil outside of
--- Cargo projects
function M.root_of(dir)
	if roots[dir] == nil then
		local found = false
		if vim.fs.root(dir, "Cargo.toml") then
			local result = platform.system(
				{ "cargo", "locate-project", "--workspace", "--message-format", "plain" },
				{ cwd = dir }
			)
			local manifest = vim.trim(result.stdout)
			found = result.code == 0 and manifest ~= "" and vim.fs.dirname(manifest) or false
		end
		roots[dir] = found
	end
	return roots[dir] or nil
end

--- The workspace root of a buffer: of its file, or of the working directory for buffers without one
function M.root(bufnr)
	bufnr = bufnr or 0
	local name = vim.api.nvim_buf_get_name(bufnr)
	local is_file = name ~= "" and vim.bo[bufnr].buftype == "" and not name:match("^%a[%w+.-]*://")
	return M.root_of(is_file and vim.fs.dirname(name) or vim.fn.getcwd())
end

--- `cargo metadata` of the workspace (its own packages only), nil when cargo can't read the project
function M.metadata(root)
	local result = platform.system({ "cargo", "metadata", "--no-deps", "--format-version", "1" }, { cwd = root })
	local ok, metadata = pcall(vim.json.decode, result.stdout)
	if result.code ~= 0 or not ok then
		vim.notify("cargo metadata failed:\n" .. result.stderr, vim.log.levels.ERROR)
		return nil
	end
	return metadata
end

--- Every target of the workspace of one of these kinds ("bin", "example", "test", "lib", ...):
--- a list of { package, name, kind, dir }
function M.targets(root, kinds)
	local targets = {}
	for _, package in ipairs((M.metadata(root) or {}).packages or {}) do
		for _, target in ipairs(package.targets) do
			for _, kind in ipairs(target.kind) do
				if vim.list_contains(kinds, kind) then
					table.insert(targets, {
						package = package.name,
						name = target.name,
						kind = kind,
						dir = vim.fs.dirname(package.manifest_path),
					})
					break
				end
			end
		end
	end
	return targets
end

---------------------------------------------------------------------------
-- Switches
---------------------------------------------------------------------------

local function features(root)
	state.features[root] = state.features[root] or { all = false, names = {} }
	return state.features[root]
end

--- The arguments the switches add to a cargo command
function M.flags(root)
	local flags = {}
	if state.release then
		table.insert(flags, "--release")
	end
	if state.package[root] then
		vim.list_extend(flags, { "--package", state.package[root] })
	end
	local chosen = features(root)
	local names = vim.tbl_keys(chosen.names)
	if chosen.all then
		table.insert(flags, "--all-features")
	elseif #names > 0 then
		table.sort(names)
		vim.list_extend(flags, { "--features", table.concat(names, ",") })
	end
	return flags
end

function M.statusline()
	local root = M.root(0)
	if not root then
		return ""
	end
	local flags = M.flags(root)
	return #flags > 0 and ("cargo " .. table.concat(flags, " ")) or ""
end

function M.toggle_release()
	state.release = not state.release
	vim.notify(state.release and "Cargo: release profile (--release)" or "Cargo: dev profile")
	vim.cmd("redrawstatus")
end

local function need_root()
	local root = M.root(0)
	if not root then
		vim.notify("Not inside a Cargo project", vim.log.levels.WARN)
	end
	return root
end

--- Limit every command to one package of the workspace, or to all of them again
function M.select_package()
	local root = need_root()
	local metadata = root and M.metadata(root)
	if not metadata then
		return
	end
	local names = { "(whole workspace)" }
	for _, package in ipairs(metadata.packages) do
		table.insert(names, package.name)
	end
	vim.ui.select(names, { prompt = "Cargo package" }, function(choice, index)
		if choice then
			state.package[root] = index > 1 and choice or nil
			vim.notify("Cargo: " .. (index > 1 and ("package " .. choice) or "whole workspace"))
			vim.cmd("redrawstatus")
		end
	end)
end

--- Switch features on and off, the list stays open until "Done"
function M.select_features()
	local root = need_root()
	local metadata = root and M.metadata(root)
	if not metadata then
		return
	end
	local available = {}
	for _, package in ipairs(metadata.packages) do
		if not state.package[root] or state.package[root] == package.name then
			for name in pairs(package.features or {}) do
				available[name] = true
			end
		end
	end
	local names = vim.tbl_keys(available)
	table.sort(names)
	local chosen = features(root)

	local function ask()
		local items = { "Done", (chosen.all and "[x] " or "[ ] ") .. "all features (--all-features)" }
		for _, name in ipairs(names) do
			table.insert(items, (chosen.names[name] and "[x] " or "[ ] ") .. name)
		end
		vim.ui.select(items, { prompt = "Cargo features" }, function(_, index)
			vim.cmd("redrawstatus")
			if not index or index == 1 then
				return
			end
			if index == 2 then
				chosen.all = not chosen.all
			else
				local name = names[index - 2]
				chosen.names[name] = not chosen.names[name] or nil
			end
			vim.schedule(ask)
		end)
	end
	ask()
end

---------------------------------------------------------------------------
-- Output pane
---------------------------------------------------------------------------

local output = { buf = nil, win = nil, job = nil }

--- A fresh output buffer in the pane at the bottom, a command that is still running is stopped
local function new_output()
	if output.job then
		pcall(vim.fn.jobstop, output.job)
		output.job = nil
	end
	local previous = output.buf
	output.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[output.buf].bufhidden = "hide"
	if output.win and vim.api.nvim_win_is_valid(output.win) then
		vim.api.nvim_win_set_buf(output.win, output.buf)
	else
		output.win = vim.api.nvim_open_win(output.buf, false, { split = "below", win = -1, height = 12 })
		vim.wo[output.win].number = false
		vim.wo[output.win].relativenumber = false
		vim.wo[output.win].signcolumn = "no"
	end
	if previous and vim.api.nvim_buf_is_valid(previous) then
		pcall(vim.api.nvim_buf_delete, previous, { force = true })
	end
	return output.buf
end

--- Keep showing the newest output, like `tail -f`: a terminal window only scrolls along while its
--- cursor is on the last line. Left alone while you are in the pane yourself.
local function follow(buf)
	local win = output.win
	if
		win
		and vim.api.nvim_win_is_valid(win)
		and vim.api.nvim_win_get_buf(win) == buf
		and win ~= vim.api.nvim_get_current_win()
	then
		pcall(vim.api.nvim_win_set_cursor, win, { vim.api.nvim_buf_line_count(buf), 0 })
	end
end

--- Show the output pane again after closing it, or hide it
function M.toggle_output()
	if output.win and vim.api.nvim_win_is_valid(output.win) then
		vim.api.nvim_win_close(output.win, false)
		output.win = nil
	elseif output.buf and vim.api.nvim_buf_is_valid(output.buf) then
		output.win = vim.api.nvim_open_win(output.buf, false, { split = "below", win = -1, height = 12 })
		follow(output.buf)
	else
		vim.notify("No cargo output yet")
	end
end

--- Run a cargo command in the pane as a real terminal: colors, progress bars, and a program started by
--- `cargo run` can read the keyboard (enter the pane and press i)
local function run_in_terminal(root, args)
	vim.cmd.wall({ mods = { silent = true, emsg_silent = true } })
	local buf = new_output()
	local command = vim.list_extend({ "cargo" }, args)
	vim.api.nvim_buf_call(buf, function()
		output.job = vim.fn.jobstart(command, {
			term = true,
			cwd = root,
			on_exit = function(job)
				if output.job == job then
					output.job = nil
				end
			end,
		})
	end)
	vim.schedule(function()
		follow(buf)
	end)
end

---------------------------------------------------------------------------
-- Compiling, with the diagnostics in the quickfix list
---------------------------------------------------------------------------

--- A quickfix entry for a compiler message (from --message-format=json), nil for notes without a place
local function quickfix_item(message, root)
	if message.level ~= "error" and message.level ~= "warning" then
		return nil
	end
	local span
	for _, candidate in ipairs(message.spans or {}) do
		if candidate.is_primary then
			span = candidate
			break
		end
	end
	if not span then
		return nil
	end
	local file = span.file_name
	if not (file:match("^/") or file:match("^%a:[/\\]")) then
		file = platform.join(root, file)
	end
	local code = type(message.code) == "table" and message.code.code or nil
	return {
		filename = file,
		lnum = span.line_start,
		col = span.column_start,
		end_lnum = span.line_end,
		end_col = span.column_end,
		type = message.level == "error" and "E" or "W",
		text = message.message .. (code and (" [" .. code .. "]") or ""),
	}
end

--- Run build/check/clippy: cargo reports as JSON, the readable form of each message goes to the pane
--- and its location to the quickfix list
local function compile(root, args)
	vim.cmd.wall({ mods = { silent = true, emsg_silent = true } })
	local buf = new_output()
	local terminal = vim.api.nvim_open_term(buf, {})
	local title = "cargo " .. table.concat(args, " ")
	local function write(text)
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(vim.api.nvim_chan_send, terminal, (text:gsub("\r?\n", "\r\n")))
			follow(buf)
		end
	end
	write("\27[2m$ " .. title .. "\27[0m\n")

	local command = vim.list_extend({ "cargo" }, args)
	vim.list_extend(command, { "--message-format=json-diagnostic-rendered-ansi", "--color=always" })

	local items, errors, warnings = {}, 0, 0
	local pending = "" -- a JSON line can arrive in pieces
	local function on_json(line)
		local ok, message = pcall(vim.json.decode, line)
		if not ok or type(message) ~= "table" then
			return write(line .. "\n") -- not JSON: something a build script printed
		end
		if message.reason ~= "compiler-message" then
			return
		end
		local diagnostic = message.message
		if type(diagnostic.rendered) == "string" then
			write(diagnostic.rendered)
		end
		local item = quickfix_item(diagnostic, root)
		if item then
			table.insert(items, item)
			errors = errors + (item.type == "E" and 1 or 0)
			warnings = warnings + (item.type == "W" and 1 or 0)
		end
	end

	output.job = vim.fn.jobstart(command, {
		cwd = root,
		on_stdout = function(_, data)
			data[1] = pending .. data[1]
			pending = table.remove(data)
			for _, line in ipairs(data) do
				if line ~= "" then
					on_json(line)
				end
			end
		end,
		on_stderr = function(_, data)
			write(table.concat(data, "\n"))
		end,
		on_exit = function(job, code)
			if output.job ~= job then
				return -- stopped because another command took over the pane
			end
			output.job = nil
			vim.fn.setqflist({}, " ", { title = title, items = items })
			local counts = string.format(
				"%d error%s, %d warning%s",
				errors,
				errors == 1 and "" or "s",
				warnings,
				warnings == 1 and "" or "s"
			)
			if code == 0 then
				vim.notify(title .. ": done" .. (warnings > 0 and (", " .. counts .. " (<leader>Cq)") or ""))
			else
				vim.notify(title .. " failed: " .. counts .. " (<leader>Cq opens the list)", vim.log.levels.ERROR)
			end
		end,
	})
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

function M.build()
	local root = need_root()
	if root then
		compile(root, vim.list_extend({ "build" }, M.flags(root)))
	end
end

function M.check()
	local root = need_root()
	if root then
		compile(root, vim.list_extend({ "check", "--all-targets" }, M.flags(root)))
	end
end

function M.clippy()
	local root = need_root()
	if root then
		compile(root, vim.list_extend({ "clippy", "--all-targets" }, M.flags(root)))
	end
end

--- cargo-nextest when it is installed, `cargo test` otherwise
function M.test()
	local root = need_root()
	if root then
		local command = platform.has("cargo-nextest") and { "nextest", "run" } or { "test" }
		run_in_terminal(root, vim.list_extend(command, M.flags(root)))
	end
end

function M.doc()
	local root = need_root()
	if root then
		local args = vim.list_extend({ "doc", "--no-deps", "--open" }, M.flags(root))
		run_in_terminal(root, args)
	end
end

--- `cargo run`, asking which binary when the project (or the chosen package) has several
function M.run()
	local root = need_root()
	if not root then
		return
	end
	local binaries = vim.tbl_filter(function(target)
		return not state.package[root] or state.package[root] == target.package
	end, M.targets(root, { "bin" }))
	if #binaries == 0 then
		vim.notify("No binary to run in this project", vim.log.levels.WARN)
		return
	end
	local function start(binary)
		local args = vim.list_extend({ "run" }, M.flags(root))
		if not state.package[root] then
			vim.list_extend(args, { "--package", binary.package })
		end
		run_in_terminal(root, vim.list_extend(args, { "--bin", binary.name }))
	end
	if #binaries == 1 then
		return start(binaries[1])
	end
	vim.ui.select(binaries, {
		prompt = "cargo run",
		format_item = function(binary)
			return binary.name == binary.package and binary.name or (binary.name .. "  (" .. binary.package .. ")")
		end,
	}, function(binary)
		if binary then
			start(binary)
		end
	end)
end

local last_command = "update"

--- Any other cargo command, typed (the switches are not added to it)
function M.exec()
	local root = need_root()
	if not root then
		return
	end
	local input = vim.trim(vim.fn.input("cargo ", last_command))
	if input ~= "" then
		last_command = input
		run_in_terminal(root, vim.split(input, "%s+"))
	end
end

function M.toggle_quickfix()
	local open = vim.fn.getqflist({ winid = 0 }).winid ~= 0
	vim.cmd(open and "cclose" or "botright copen")
end

return M
