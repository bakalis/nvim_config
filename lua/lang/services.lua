-- Services panel: every Java run configuration of the project with its state, and keys to
-- run, debug, restart and stop each of them (IntelliJ's Services tool window).
local M = {}

local namespace = vim.api.nvim_create_namespace("java-services")
local state = { buf = nil, win = nil, root = nil, items = {}, line_item = {} }

local function java()
	return require("lang.java")
end

local function dap()
	return require("dap")
end

-- name of a configuration -> its running dap session
local function running_sessions()
	local result = {}
	for _, session in pairs(dap().sessions()) do
		result[session.config.name] = session
	end
	return result
end

local function is_open()
	return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

local function render()
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return
	end
	local sessions = running_sessions()
	local lines = { " Java Services  " .. vim.fn.fnamemodify(state.root or "", ":t"), "" }
	local marks = { { 0, "JavaServicesTitle" } }
	state.line_item = {}

	if #state.items == 0 then
		table.insert(lines, " No run configurations, press e to create launch.json")
		table.insert(marks, { #lines - 1, "JavaServicesStopped" })
	end
	for index, item in ipairs(state.items) do
		local session = sessions[item.name]
		local text = (session and " ● " or " ○ ") .. item.name
		if session then
			text = text .. "  " .. (session.config.noDebug and "running" or "debugging")
		end
		table.insert(lines, text)
		state.line_item[#lines] = index
		table.insert(marks, {
			#lines - 1,
			session and (session.config.noDebug and "JavaServicesRunning" or "JavaServicesDebug") or "JavaServicesStopped",
		})
	end

	vim.list_extend(lines, {
		"",
		" <CR> run / open output   d debug",
		" r restart   s stop   S stop all",
		" a activate debug session",
		" e edit configs   R refresh   q close",
	})
	for row = #lines - 4, #lines - 1 do
		table.insert(marks, { row, "JavaServicesStopped" })
	end

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
	for _, mark in ipairs(marks) do
		vim.api.nvim_buf_set_extmark(state.buf, namespace, mark[1], 0, { line_hl_group = mark[2] })
	end
end

local function refresh()
	if not is_open() then
		return
	end
	-- saved configurations show up immediately, discovered main classes when jdtls answers
	state.items = vim.deepcopy(java().launch_configs(state.root))
	render()
	java().project_configs(state.root, function(configs)
		state.items = configs
		vim.schedule(render)
	end)
end

local function current_item()
	local index = state.line_item[vim.api.nvim_win_get_cursor(0)[1]]
	return index and state.items[index]
end

local function start(item, debug)
	local config = vim.deepcopy(item)
	config.noDebug = not debug
	-- the panel buffer has no filetype, nvim-dap uses it to set up the terminal
	dap().run(config, { new = true, filetype = "java" })
end

local function stop(session)
	dap().set_session(session)
	dap().terminate()
end

local function when_stopped(name, callback, tries)
	tries = tries or 60
	if tries == 0 or not running_sessions()[name] then
		return callback()
	end
	vim.defer_fn(function()
		when_stopped(name, callback, tries - 1)
	end, 100)
end

local function restart(item, debug)
	local session = running_sessions()[item.name]
	if not session then
		return start(item, debug)
	end
	stop(session)
	when_stopped(item.name, function()
		start(item, debug)
	end)
end

local function open_output(session)
	local buf = session.term_buf
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		vim.notify("No output for " .. session.config.name, vim.log.levels.INFO)
		return
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_buf(win) == buf then
			vim.api.nvim_set_current_win(win)
			return
		end
	end
	vim.cmd("botright 15split")
	vim.api.nvim_win_set_buf(0, buf)
	vim.cmd("normal! G")
end

local function set_keymaps(buf)
	local map = function(keys, func, desc)
		vim.keymap.set("n", keys, func, { buffer = buf, nowait = true, desc = "Services: " .. desc })
	end

	map("<CR>", function()
		local item = current_item()
		if not item then
			return
		end
		local session = running_sessions()[item.name]
		if session then
			open_output(session)
		else
			start(item, false)
		end
	end, "Run / open output")
	map("d", function()
		local item = current_item()
		if item then
			restart(item, true)
		end
	end, "Debug")
	map("r", function()
		local item = current_item()
		if item then
			local session = running_sessions()[item.name]
			restart(item, session and not session.config.noDebug or false)
		end
	end, "Restart")
	map("s", function()
		local item = current_item()
		local session = item and running_sessions()[item.name]
		if session then
			stop(session)
		end
	end, "Stop")
	map("S", function()
		for _, session in pairs(running_sessions()) do
			stop(session)
		end
	end, "Stop all")
	map("a", function()
		local item = current_item()
		local session = item and running_sessions()[item.name]
		if session then
			dap().set_session(session)
			vim.notify("Active debug session: " .. item.name)
		end
	end, "Activate debug session")
	map("e", function()
		vim.cmd("wincmd p")
		java().edit_configs(state.root)
	end, "Edit configurations")
	map("R", refresh, "Refresh")
	map("q", M.close, "Close")
end

function M.close()
	if is_open() then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
end

function M.open()
	if is_open() then
		vim.api.nvim_set_current_win(state.win)
		return
	end

	local buffer_name = vim.api.nvim_buf_get_name(0)
	state.root = vim.bo.filetype == "java" and java().find_root(buffer_name) or state.root or vim.fn.getcwd()

	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[state.buf].buftype = "nofile"
		vim.bo[state.buf].bufhidden = "hide"
		vim.bo[state.buf].swapfile = false
		vim.bo[state.buf].filetype = "java-services"
		vim.api.nvim_buf_set_name(state.buf, "Java Services")
		set_keymaps(state.buf)
	end

	vim.cmd("botright vsplit")
	state.win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(state.win, state.buf)
	vim.api.nvim_win_set_width(state.win, 44)
	for option, value in pairs({
		number = false,
		relativenumber = false,
		signcolumn = "no",
		wrap = false,
		cursorline = true,
		winfixwidth = true,
	}) do
		vim.wo[state.win][option] = value
	end
	refresh()
	pcall(vim.api.nvim_win_set_cursor, state.win, { 3, 0 })
end

function M.toggle()
	if is_open() then
		M.close()
	else
		M.open()
	end
end

local function define_highlights()
	vim.api.nvim_set_hl(0, "JavaServicesTitle", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "JavaServicesRunning", { link = "DiagnosticOk", default = true })
	vim.api.nvim_set_hl(0, "JavaServicesDebug", { link = "DiagnosticWarn", default = true })
	vim.api.nvim_set_hl(0, "JavaServicesStopped", { link = "Comment", default = true })
end
define_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("java-services-highlights", { clear = true }),
	callback = define_highlights,
})

-- keep the list in step with the sessions, whoever started or stopped them
local function update()
	vim.defer_fn(render, 150)
end
for _, event in ipairs({ "event_initialized", "event_terminated", "event_exited", "disconnect" }) do
	require("dap").listeners.after[event]["java-services"] = update
end

return M
