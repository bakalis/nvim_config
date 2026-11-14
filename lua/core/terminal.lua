-- Floating, numbered terminals. <C-\> shows or hides the last used one, `2<C-\>` terminal number 2, and so on.
-- A hidden terminal keeps its shell running, the next toggle brings the same session back.
local platform = require("core.platform")

local M = {}

local terminals = {} -- [number] = { buf = ..., win = ... }
local last = 1

local function window_open(terminal)
	return terminal ~= nil and terminal.win ~= nil and vim.api.nvim_win_is_valid(terminal.win)
end

local function buffer_alive(terminal)
	return terminal ~= nil and terminal.buf ~= nil and vim.api.nvim_buf_is_valid(terminal.buf)
end

local function float_config(number)
	local width = math.floor(vim.o.columns * 0.85)
	local height = math.floor((vim.o.lines - vim.o.cmdheight) * 0.8)
	return {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2) - 1,
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " Terminal " .. number .. " ",
		title_pos = "center",
	}
end

local function hide(number)
	local terminal = terminals[number]
	if window_open(terminal) then
		vim.api.nvim_win_close(terminal.win, true) -- only the window, the buffer and its shell stay
	end
	if terminal then
		terminal.win = nil
	end
end

local function hide_all()
	for number in pairs(terminals) do
		hide(number)
	end
end

local function start_shell(terminal, number)
	vim.api.nvim_buf_call(terminal.buf, function()
		vim.fn.jobstart(platform.shell(), { term = true, cwd = vim.fn.getcwd() })
	end)
	vim.bo[terminal.buf].bufhidden = "hide"
	vim.b[terminal.buf].floating_terminal = number
	-- keys of the floating terminals only, other terminals (debugger output, ...) keep the defaults
	local function key(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { buffer = terminal.buf, desc = desc })
	end
	key("t", "<C-\\>", function()
		M.toggle(number)
	end, "Hide floating terminal (it keeps running)")
	key("t", "<Esc><Esc>", "<C-\\><C-n>", "Terminal normal mode (scroll, copy)")
	-- in normal mode Escape and q hide the float
	key("n", "<Esc>", function()
		M.toggle(number)
	end, "Hide floating terminal (it keeps running)")
	key("n", "q", function()
		M.toggle(number)
	end, "Hide floating terminal (it keeps running)")
	-- when the shell exits (exit, Ctrl-D) the window and the buffer go away with it
	vim.api.nvim_create_autocmd("TermClose", {
		buffer = terminal.buf,
		once = true,
		callback = function(event)
			vim.schedule(function()
				if terminals[number] and terminals[number].buf == event.buf then
					hide(number)
					terminals[number] = nil
				end
				if vim.api.nvim_buf_is_valid(event.buf) then
					vim.api.nvim_buf_delete(event.buf, { force = true })
				end
			end)
		end,
	})
end

--- Show terminal `number`, starting its shell the first time. Any other floating terminal is hidden.
function M.show(number)
	hide_all()
	local terminal = terminals[number]
	if not buffer_alive(terminal) then
		terminal = { buf = vim.api.nvim_create_buf(false, true), cwd = vim.fn.getcwd() }
		terminals[number] = terminal
		terminal.win = vim.api.nvim_open_win(terminal.buf, true, float_config(number))
		start_shell(terminal, number)
	else
		terminal.win = vim.api.nvim_open_win(terminal.buf, true, float_config(number))
	end
	last = number
	vim.cmd("startinsert")
end

--- Number of the floating terminal in the current window, nil in any other window
function M.current()
	local number = vim.b.floating_terminal
	if number and window_open(terminals[number]) and terminals[number].win == vim.api.nvim_get_current_win() then
		return number
	end
end

--- Hide terminal `number` when it is showing, show it otherwise
function M.toggle(number)
	number = number or M.current() or last
	if window_open(terminals[number]) then
		hide(number)
		vim.cmd("stopinsert")
	else
		M.show(number)
	end
end

---------------------------------------------------------------------------
-- The menu: what is open, and a way to stop it
---------------------------------------------------------------------------

--- Numbers of the terminals that exist, ascending
local function numbers()
	local result = {}
	for number, terminal in pairs(terminals) do
		if buffer_alive(terminal) then
			table.insert(result, number)
		end
	end
	table.sort(result)
	return result
end

--- What the shell of a terminal is running right now: a program name, nil when it is idle at its prompt
local function busy_with(terminal)
	local job = vim.b[terminal.buf].terminal_job_id
	local ok, children = pcall(function()
		return vim.api.nvim_get_proc_children(vim.fn.jobpid(job))
	end)
	if ok and children and #children > 0 then
		local named, process = pcall(vim.api.nvim_get_proc, children[1])
		return named and process and process.name or "busy"
	end
end

--- Last line of output, to recognise a terminal by
local function last_output(terminal)
	local lines = vim.api.nvim_buf_get_lines(terminal.buf, 0, -1, false)
	for index = #lines, 1, -1 do
		local text = vim.trim(lines[index])
		if text ~= "" then
			return text
		end
	end
	return ""
end

--- Whether the terminal buffer is a shell waiting at its prompt. A program that owns the terminal (lazygit, vim,
--- htop) or something the shell is running (npm run dev) makes this false. Unknown means false, the safe answer.
function M.at_shell_prompt(buf)
	local job = vim.b[buf].terminal_job_id
	if not job then
		return false
	end
	local ok, idle = pcall(function()
		local pid = vim.fn.jobpid(job)
		return platform.is_shell(vim.api.nvim_get_proc(pid).name) and #vim.api.nvim_get_proc_children(pid) == 0
	end)
	return ok and idle
end

--- Stop terminal `number`: its window goes, its shell and everything it started are terminated
function M.kill(number)
	local terminal = terminals[number]
	if not terminal then
		return false
	end
	hide(number)
	terminals[number] = nil
	if buffer_alive(terminal) then
		local job = vim.b[terminal.buf].terminal_job_id
		if job then
			pcall(vim.fn.jobstop, job)
		end
		pcall(vim.api.nvim_buf_delete, terminal.buf, { force = true })
	end
	if last == number then
		last = 1
	end
	return true
end

function M.kill_all()
	local count = 0
	for _, number in ipairs(numbers()) do
		count = count + (M.kill(number) and 1 or 0)
	end
	return count
end

local function entries()
	local result = {}
	for _, number in ipairs(numbers()) do
		local terminal = terminals[number]
		local command = busy_with(terminal)
		table.insert(result, {
			number = number,
			visible = window_open(terminal),
			cwd = vim.fn.fnamemodify(terminal.cwd or "", ":t"), -- the folder name, the full path is too long for a row
			command = command,
			output = last_output(terminal),
			buf = terminal.buf,
		})
	end
	return result
end

local function describe(entry)
	local output = #entry.output > 50 and (entry.output:sub(1, 49) .. "…") or entry.output
	return string.format(
		"%s Terminal %d   %-7s  %s   %s",
		entry.visible and "●" or "○",
		entry.number,
		entry.command or "idle",
		entry.cwd,
		output
	)
end

--- The menu: Enter shows a terminal, Ctrl-X stops the highlighted one (Tab selects several first)
function M.menu()
	if #numbers() == 0 then
		vim.notify("No floating terminals yet, <leader>ot opens one")
		return
	end

	local ok, pickers = pcall(require, "telescope.pickers")
	if not ok then
		-- without telescope: pick one to show
		local items = entries()
		vim.ui.select(items, { prompt = "Terminals", format_item = describe }, function(item)
			if item then
				M.show(item.number)
			end
		end)
		return
	end

	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	local function finder()
		return finders.new_table({
			results = entries(),
			entry_maker = function(entry)
				return { value = entry, display = describe(entry), ordinal = describe(entry) }
			end,
		})
	end

	pickers
		.new({
			prompt_title = "Terminals   (Enter: show · Tab: select · Ctrl-X: stop selected)",
			finder = finder(),
			sorter = conf.generic_sorter({}),
			sorting_strategy = "ascending",
			layout_config = { prompt_position = "top" },
			previewer = previewers.new_buffer_previewer({
				title = "Output",
				define_preview = function(self, entry)
					local source = entry.value.buf
					local lines = vim.api.nvim_buf_is_valid(source) and vim.api.nvim_buf_get_lines(source, 0, -1, false) or {}
					while #lines > 0 and vim.trim(lines[#lines]) == "" do
						table.remove(lines)
					end
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
					pcall(vim.api.nvim_win_call, self.state.winid, function()
						vim.cmd("normal! G")
					end)
				end,
			}),
			attach_mappings = function(prompt_buffer, map)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_buffer)
					if entry then
						vim.schedule(function()
							M.show(entry.value.number)
						end)
					end
				end)

				local function stop_selected()
					local picker = action_state.get_current_picker(prompt_buffer)
					local chosen = picker:get_multi_selection()
					if #chosen == 0 then
						chosen = { action_state.get_selected_entry() }
					end
					local stopped = {}
					for _, entry in ipairs(chosen) do
						if entry and M.kill(entry.value.number) then
							table.insert(stopped, entry.value.number)
						end
					end
					if #stopped > 0 then
						vim.notify("Stopped terminal " .. table.concat(stopped, ", "))
					end
					if #numbers() == 0 then
						actions.close(prompt_buffer)
					else
						picker:refresh(finder(), { reset_prompt = false })
					end
				end
				map({ "i", "n" }, "<C-x>", stop_selected)
				map("n", "dd", stop_selected)
				return true
			end,
		})
		:find()
end

function M.setup()
	-- <C-\> toggles the last used terminal, <leader>ot terminal 1. A count picks the terminal for both (2<C-\>, 2<leader>ot).
	-- Pressed inside a floating terminal, either key hides that one.
	local function map_toggle()
		local function count()
			return vim.v.count > 0 and vim.v.count or nil
		end
		vim.keymap.set("n", "<C-\\>", function()
			M.toggle(count())
		end, { desc = "Toggle floating terminal (last used, count: terminal number)" })
		vim.keymap.set("n", "<leader>ot", function()
			M.toggle(count() or M.current() or 1)
		end, { desc = "Toggle floating terminal (1, count: terminal number)" })
	end
	map_toggle()
	-- vim-tmux-navigator maps <C-\> too ("previous tmux pane") and loads later, so this is set again after the plugins
	vim.api.nvim_create_autocmd("User", { pattern = "VeryLazy", once = true, callback = map_toggle })

	vim.keymap.set("n", "<leader>ol", M.menu, { desc = "List floating terminals (and stop them)" })
	vim.api.nvim_create_user_command("Terminals", M.menu, { desc = "List floating terminals (and stop them)" })
	vim.api.nvim_create_user_command("TerminalKill", function(command)
		local number = tonumber(command.args) or M.current() or last
		if not M.kill(number) then
			vim.notify("No terminal " .. number, vim.log.levels.WARN)
		end
	end, { nargs = "?", desc = "Stop a floating terminal and what runs in it" })
	vim.api.nvim_create_user_command("TerminalKillAll", function()
		vim.notify("Stopped " .. M.kill_all() .. " terminal(s)")
	end, { desc = "Stop every floating terminal" })

	vim.api.nvim_create_user_command("Terminal", function(command)
		local number = tonumber(command.args)
		if command.args ~= "" and not number then
			vim.notify("Terminal: the argument is a number, for example :Terminal 2", vim.log.levels.ERROR)
			return
		end
		M.toggle(number)
	end, { nargs = "?", desc = "Toggle a floating terminal" })

	-- keep the float centered when the window is resized
	vim.api.nvim_create_autocmd("VimResized", {
		group = vim.api.nvim_create_augroup("floating-terminal", { clear = true }),
		callback = function()
			for number, terminal in pairs(terminals) do
				if window_open(terminal) then
					vim.api.nvim_win_set_config(terminal.win, float_config(number))
				end
			end
		end,
	})
end

return M
