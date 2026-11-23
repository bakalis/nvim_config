-- Runs a terminal app (lazysvn, ...) in a big floating window. The app is started fresh each time and the window
-- closes when the app exits, so q inside the app returns you to the editor.
local M = {}

-- Directory of the nearest ancestor holding the marker (e.g. ".svn"), starting at the current file's folder.
local function find_root(marker)
	local start = vim.api.nvim_buf_get_name(0)
	start = start ~= "" and vim.fs.dirname(start) or vim.fn.getcwd()
	local found = vim.fs.find(marker, { upward = true, path = start, limit = 1 })[1]
	return found and vim.fs.dirname(found) or nil
end

---@param command string executable to run
---@param opts { title?: string, marker?: string, install?: string }
function M.open(command, opts)
	opts = opts or {}
	if vim.fn.executable(command) == 0 then
		vim.notify(
			command .. " is not installed" .. (opts.install and (": " .. opts.install) or ""),
			vim.log.levels.ERROR
		)
		return
	end
	local cwd = vim.fn.getcwd()
	if opts.marker then
		cwd = find_root(opts.marker) or find_root(".") or cwd
		if not find_root(opts.marker) and not vim.uv.fs_stat(cwd .. "/" .. opts.marker) then
			vim.notify("No " .. opts.marker .. " found above " .. cwd, vim.log.levels.WARN)
		end
	end

	local width = math.floor(vim.o.columns * 0.92)
	local height = math.floor((vim.o.lines - vim.o.cmdheight) * 0.9)
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2) - 1,
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " " .. (opts.title or command) .. " ",
		title_pos = "center",
	})
	vim.fn.jobstart({ command }, {
		term = true,
		cwd = cwd,
		on_exit = function()
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_close(win, true)
				end
				if vim.api.nvim_buf_is_valid(buf) then
					vim.api.nvim_buf_delete(buf, { force = true })
				end
			end)
		end,
	})
	vim.bo[buf].filetype = "tui"
	vim.cmd("startinsert")
end

return M
