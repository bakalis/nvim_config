-- Tells Git and Subversion working copies apart, so keys such as <leader>gd and <leader>gv can do the right thing
-- in either. Git keeps its own tools (delta, codediff). Subversion gets the same idea built on
-- `svn diff` and `svn status`: a floating delta diff of the file against its BASE revision (the state of the last
-- update) and a picker over the changed files.
local M = {}

local function start_dir()
	local name = vim.api.nvim_buf_get_name(0)
	if name ~= "" and vim.uv.fs_stat(name) then
		return vim.fs.dirname(name)
	end
	return vim.fn.getcwd()
end

--- "git", "svn" or nil. Git wins when both are present (a git-svn clone, or a git repository inside a checkout).
function M.kind()
	local dir = start_dir()
	local git = vim.fs.find(".git", { upward = true, path = dir, limit = 1 })[1]
	local svn = vim.fs.find(".svn", { upward = true, path = dir, limit = 1 })[1]
	if git and svn then
		-- the nearer one is the repository the file belongs to; on a tie git is the one with the richer tools
		return #git >= #svn and "git" or "svn"
	end
	if git or svn then
		return git and "git" or "svn"
	end
	-- no marker folder found: ask svn itself, it knows layouts the folder search does not
	if vim.fn.executable("svn") == 1 and vim.system({ "svn", "info" }, { cwd = dir }):wait().code == 0 then
		return "svn"
	end
	return nil
end

--- True in a git working copy. Otherwise says why not and returns false, so git-only keys end with a message
--- instead of a stack trace from fugitive, codediff or telescope.
function M.require_git()
	local kind = M.kind()
	if kind == "git" then
		return true
	end
	vim.notify(
		kind == "svn" and "This is a Subversion working copy, not a git repository" or "Not in a git repository",
		vim.log.levels.WARN
	)
	return false
end

--- The same for Subversion: true in an SVN working copy, otherwise says why not.
function M.require_svn()
	local kind = M.kind()
	if kind == "svn" then
		return true
	end
	vim.notify(
		kind == "git" and "This is a git repository, not a Subversion working copy" or "Not in a Subversion working copy",
		vim.log.levels.WARN
	)
	return false
end

--- Wraps a git-only action (an ex command string or a function) with the check above, for use as a key's rhs.
function M.git_only(action)
	return function()
		if not M.require_git() then
			return
		end
		if type(action) == "string" then
			vim.cmd(action)
		else
			action()
		end
	end
end

--- A key's rhs with a Subversion alternative: in an SVN working copy runs handlers.svn, otherwise the git action
--- (an ex command or a function) behind the usual git check.
function M.dispatch(handlers, git_action)
	local git = M.git_only(git_action)
	return function()
		if M.kind() == "svn" then
			handlers.svn()
		else
			git()
		end
	end
end

--- Top of the Subversion working copy that holds the current file.
local function svn_root()
	local result = vim.system({ "svn", "info", "--show-item", "wc-root" }, { cwd = start_dir(), text = true }):wait()
	if result.code == 0 and vim.trim(result.stdout) ~= "" then
		return vim.trim(result.stdout)
	end
	local found = vim.fs.find(".svn", { upward = true, path = start_dir(), limit = 1 })[1]
	return found and vim.fs.dirname(found) or vim.fn.getcwd()
end

--- Runs a shell command in a floating terminal window covering 95% of the screen (like the git diff float).
--- q closes it. on_close, when given, runs after the float is gone.
local function float_command(command, cwd, on_close)
	local width = math.floor(vim.o.columns * 0.95)
	local height = math.floor(vim.o.lines * 0.95)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
	})
	vim.fn.jobstart(command, { term = true, cwd = cwd })
	vim.cmd("startinsert")
	if on_close then
		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = buf,
			once = true,
			callback = function()
				vim.schedule(on_close)
			end,
		})
	end
	vim.keymap.set({ "t", "n" }, "q", function()
		vim.cmd("stopinsert")
		vim.cmd("bd!")
	end, { buffer = buf, silent = true, desc = "Close the diff" })
end

local function through_delta()
	return vim.fn.executable("delta") == 1 and " | delta" or ""
end

--- The diff of the current file against BASE in a floating window, rendered by delta like the git one (<leader>gd).
function M.svn_file_diff()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		vim.notify("This buffer has no file", vim.log.levels.WARN)
		return
	end
	-- relative to the file, so the header shows only its name
	float_command(
		"svn diff -- " .. vim.fn.shellescape(vim.fs.basename(file)) .. through_delta(),
		vim.fs.dirname(file)
	)
end

--- Shows `text` in a small centered float, q closes it.
local function float_text(text, title)
	local lines = vim.split(vim.trim(text), "\n", { plain = true })
	local width = math.min(math.floor(vim.o.columns * 0.8), 120)
	local height = math.min(#lines, math.floor(vim.o.lines * 0.7))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
	})
	vim.wo.wrap = true
	vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close" })
	vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, desc = "Close" })
end

--- Blame of the current file: a column with the revision, author and date of every line, scrolling together with the
--- file, like fugitive's `:Git blame`. <CR> on a line shows the log message of its revision, q closes the column.
local blame_windows = {} -- [file window] = its blame column, so a second <leader>gb does not open another one

function M.svn_blame()
	local current = vim.api.nvim_get_current_win()
	for work, blame in pairs(blame_windows) do
		if vim.api.nvim_win_is_valid(blame) and (current == work or current == blame) then
			return -- already open for this file
		end
		blame_windows[work] = nil
	end
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		vim.notify("This buffer has no file", vim.log.levels.WARN)
		return
	end
	local result = vim.system({ "svn", "blame", "--xml", "--", file }, { text = true }):wait()
	if result.code ~= 0 then
		local reason = vim.trim(result.stderr or "")
		vim.notify("svn blame failed: " .. (reason ~= "" and reason or "is this file under version control?"), vim.log.levels.ERROR)
		return
	end

	-- one <entry line-number="N"> per line; lines that are not committed yet have no <commit>
	local xml = result.stdout
	local starts = {}
	for position in xml:gmatch("()<entry[%s>]") do
		table.insert(starts, position)
	end
	local rows, revisions = {}, {}
	for index, position in ipairs(starts) do
		local entry = xml:sub(position, (starts[index + 1] or #xml + 1) - 1)
		local line = tonumber(entry:match('line%-number="(%d+)"'))
		if line then
			local revision = entry:match('revision="(%d+)"')
			if revision then
				local author = entry:match("<author>(.-)</author>") or "?"
				local date = (entry:match("<date>(.-)</date>") or ""):sub(1, 10)
				rows[line] = { revision = revision, text = string.format("%-6s %-12.12s %s", "r" .. revision, author, date) }
				revisions[tonumber(revision)] = true
			else
				rows[line] = { text = "uncommitted" }
			end
		end
	end

	local work_win = vim.api.nvim_get_current_win()
	local work_lines = vim.api.nvim_buf_line_count(0)
	local lines, width = {}, 0
	for line = 1, work_lines do
		lines[line] = rows[line] and rows[line].text or ""
		width = math.max(width, vim.fn.strdisplaywidth(lines[line]))
	end

	-- each revision gets its own colour, oldest to newest
	local palette = { "Identifier", "String", "Type", "Constant", "Special", "Statement", "Function" }
	local ordered = vim.tbl_keys(revisions)
	table.sort(ordered)
	local colour = {}
	for index, revision in ipairs(ordered) do
		colour[tostring(revision)] = palette[(index - 1) % #palette + 1]
	end

	vim.cmd("leftabove vnew")
	local blame_win = vim.api.nvim_get_current_win()
	local blame_buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(blame_buf, 0, -1, false, lines)
	local namespace = vim.api.nvim_create_namespace("svn-blame")
	for line, row in pairs(rows) do
		vim.api.nvim_buf_set_extmark(blame_buf, namespace, line - 1, 0, {
			end_col = #lines[line],
			hl_group = row.revision and colour[row.revision] or "Comment",
		})
	end
	vim.bo[blame_buf].buftype = "nofile"
	vim.bo[blame_buf].bufhidden = "wipe"
	vim.bo[blame_buf].buflisted = false -- not a buffer of its own: no bufferline tab, not reachable with :bnext
	vim.bo[blame_buf].swapfile = false
	vim.bo[blame_buf].modifiable = false
	vim.bo[blame_buf].filetype = "svnblame"
	vim.api.nvim_win_set_width(blame_win, width + 1)
	for _, win in ipairs({ blame_win, work_win }) do
		vim.wo[win].scrollbind = true
		vim.wo[win].cursorbind = true
	end
	vim.wo[blame_win].wrap = false
	vim.wo[blame_win].number = false
	vim.wo[blame_win].relativenumber = false
	vim.wo[blame_win].signcolumn = "no"
	vim.wo[blame_win].foldcolumn = "0"
	vim.wo[blame_win].winfixwidth = true
	vim.wo[blame_win].winfixbuf = true -- <Tab> and :bnext cannot swap the blame out of its window
	vim.cmd("syncbind")
	vim.api.nvim_set_current_win(work_win)
	blame_windows[work_win] = blame_win

	local function close()
		if vim.api.nvim_win_is_valid(blame_win) then
			vim.api.nvim_win_close(blame_win, true)
		end
	end
	vim.keymap.set("n", "q", close, { buffer = blame_buf, desc = "Close the blame column" })
	vim.keymap.set("n", "<CR>", function()
		local row = rows[vim.fn.line(".")]
		if not (row and row.revision) then
			vim.notify("Not committed yet", vim.log.levels.INFO)
			return
		end
		local log = vim.system({ "svn", "log", "-v", "-r", row.revision }, { cwd = vim.fs.dirname(file), text = true }):wait()
		float_text(log.stdout ~= "" and log.stdout or (log.stderr or ""), "svn r" .. row.revision)
	end, { buffer = blame_buf, desc = "Show the log message of this revision" })
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = blame_buf,
		once = true,
		callback = function()
			if vim.api.nvim_win_is_valid(work_win) then
				vim.wo[work_win].scrollbind = false
				vim.wo[work_win].cursorbind = false
			end
		end,
	})
end

--- The trunk, branches and tags next to the one the working copy is on, for the branch pickers:
--- { targets = { { label, url } }, relative = "^/proj/trunk", wc_root = ... }. nil (after saying why) when there are none.
local function svn_targets()
	local dir = start_dir()
	local function info(item)
		local r = vim.system({ "svn", "info", "--show-item", item }, { cwd = dir, text = true }):wait()
		return r.code == 0 and vim.trim(r.stdout) or nil
	end
	local root_url, relative = info("repos-root-url"), info("relative-url")
	local wc_root = svn_root()
	if not (root_url and relative) then
		vim.notify("svn info failed: is this a Subversion working copy?", vim.log.levels.ERROR)
		return nil
	end
	-- the project folder holds trunk/, branches/ and tags/: everything in front of the one we are in
	local project = relative:match("^(.-)/trunk") or relative:match("^(.-)/branches/") or relative:match("^(.-)/tags/")
	if not project then
		vim.notify("No trunk/branches/tags layout found for " .. relative, vim.log.levels.WARN)
		return nil
	end
	local base_url = root_url .. project:gsub("^%^", "") -- "^/proj" -> ".../proj"

	local function list(folder)
		local r = vim.system({ "svn", "ls", base_url .. "/" .. folder }, { text = true }):wait()
		local names = {}
		for _, name in ipairs(r.code == 0 and vim.split(r.stdout, "\n", { trimempty = true }) or {}) do
			table.insert(names, { label = folder .. "/" .. name:gsub("/$", ""), url = base_url .. "/" .. folder .. "/" .. name:gsub("/$", "") })
		end
		return names
	end
	local targets = {}
	if vim.system({ "svn", "info", "--show-item", "url", base_url .. "/trunk" }, { text = true }):wait().code == 0 then
		table.insert(targets, { label = "trunk", url = base_url .. "/trunk" })
	end
	vim.list_extend(targets, list("branches"))
	vim.list_extend(targets, list("tags"))
	local here = root_url .. relative:gsub("^%^", "")
	targets = vim.tbl_filter(function(target)
		return target.url ~= here
	end, targets)
	if #targets == 0 then
		vim.notify("No other branch found in " .. base_url, vim.log.levels.INFO)
		return nil
	end
	return { targets = targets, relative = relative, wc_root = wc_root, base_url = base_url }

end

--- Compare the working copy with a branch, tag or trunk of the repository (<leader>gB): pick the branch, then the
--- files that differ from it. <CR> shows the diff of a file in the float. The diff reads "branch -> working copy",
--- so choosing trunk shows what your branch changes.
function M.svn_compare_branch()
	local found = svn_targets()
	if not found then
		return
	end
	local targets, relative, wc_root = found.targets, found.relative, found.wc_root

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	local function pick_file(target)
		local r = vim.system({ "svn", "diff", "--summarize", "--old=" .. target.url, "--new=." }, { cwd = wc_root, text = true }):wait()
		local files = {}
		for _, line in ipairs(r.code == 0 and vim.split(r.stdout, "\n", { trimempty = true }) or {}) do
			local flag, url = line:match("^(%u)%s+(%S.*)$") -- property-only changes start with a blank and are skipped
			local file = flag and url:sub(#target.url + 2)
			if file and file ~= "" and not file:match("/$") and not vim.uv.fs_stat(wc_root .. "/" .. file .. "/.") then
				table.insert(files, { flag = flag, file = file })
			end
		end
		if #files == 0 then
			vim.notify("No file differs from " .. target.label, vim.log.levels.INFO)
			return
		end
		local function diff_command(file)
			return { "svn", "diff", "--old=" .. target.url, "--new=.", "--", file }
		end
		-- reopened when the diff float closes, on the file that was just viewed
		local function open_picker(selected)
		pickers
			.new({}, {
				prompt_title = "Working copy against " .. target.label,
				default_selection_index = selected,
				finder = finders.new_table({
					results = files,
					entry_maker = function(entry)
						return { value = entry, display = string.format("%-2s %s", entry.flag, entry.file), ordinal = entry.file }
					end,
				}),
				sorter = conf.generic_sorter({}),
				previewer = previewers.new_buffer_previewer({
					title = "svn diff",
					define_preview = function(self, entry)
						local diff = vim.system(diff_command(entry.value.file), { cwd = wc_root, text = true }):wait()
						vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(diff.stdout, "\n", { plain = true }))
						vim.bo[self.state.bufnr].filetype = "diff"
					end,
				}),
				attach_mappings = function(prompt_bufnr)
					actions.select_default:replace(function()
						local entry = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if entry then
							local escaped = vim.tbl_map(vim.fn.shellescape, diff_command(entry.value.file))
							float_command(table.concat(escaped, " ") .. through_delta(), wc_root, function()
								open_picker(entry.index)
							end)
						end
					end)
					return true
				end,
			})
			:find()
		end
		open_picker()
	end

	pickers
		.new({}, {
			prompt_title = "Compare " .. relative .. " with…",
			finder = finders.new_table({
				results = targets,
				entry_maker = function(target)
					return { value = target, display = target.label, ordinal = target.label }
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if entry then
						pick_file(entry.value)
					end
				end)
				return true
			end,
		})
		:find()
end

--- Splits the output of `svn diff` into one block per file: { file, text, action = "A" | "D" | "M" }.
local function split_diff(text)
	local blocks, current = {}, nil
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local name = line:match("^Index: (.+)$")
		if name then
			current = { file = name, lines = { line } }
			table.insert(blocks, current)
		elseif current then
			table.insert(current.lines, line)
		end
	end
	for _, block in ipairs(blocks) do
		block.text = table.concat(block.lines, "\n")
		block.action = block.text:find("\n%-%-%- [^\n]*%(nonexistent%)") and "A"
			or (block.text:find("\n%+%+%+ [^\n]*%(nonexistent%)") and "D" or "M")
	end
	return blocks
end

--- Shows text in the delta float (a temporary file keeps the quoting simple).
local function float_text_through_delta(text)
	local tmp = vim.fn.tempname()
	vim.fn.writefile(vim.split(text, "\n", { plain = true }), tmp)
	float_command((vim.fn.executable("delta") == 1 and "delta < " or "cat ") .. vim.fn.shellescape(tmp))
end

--- History browser: pick a revision, see what it changed. scope "file" is the history of the current file, "repo" the
--- history of the whole working copy (<leader>gh and <leader>gH). In the revision picker <CR> shows the diff of the
--- revision in the delta float for a file, and its list of changed files for the working copy (then <CR> shows
--- one file). <C-d> shows the whole diff of the revision. The preview shows the message and the diff.
function M.svn_history(scope)
	local file = vim.api.nvim_buf_get_name(0)
	local target, cwd
	if scope == "file" then
		if file == "" then
			vim.notify("This buffer has no file", vim.log.levels.WARN)
			return
		end
		cwd = vim.fs.dirname(file)
		target = vim.fs.basename(file)
	else
		cwd = svn_root()
		target = "."
	end
	-- HEAD:1 because a folder stays at the revision of its last update, which would hide newer commits
	local result = vim.system({ "svn", "log", "--xml", "-r", "HEAD:1", "-l", "300", "--", target }, { cwd = cwd, text = true }):wait()
	if result.code ~= 0 then
		vim.notify("svn log failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
		return
	end

	local xml = result.stdout
	local starts, revisions = {}, {}
	for position in xml:gmatch("()<logentry[%s>]") do
		table.insert(starts, position)
	end
	for index, position in ipairs(starts) do
		local entry = xml:sub(position, (starts[index + 1] or #xml + 1) - 1)
		local revision = tonumber(entry:match('revision="(%d+)"'))
		if revision then
			local message = vim.trim(entry:match("<msg>(.-)</msg>") or "")
			message = message:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&")
			table.insert(revisions, {
				revision = revision,
				author = entry:match("<author>(.-)</author>") or "?",
				date = (entry:match("<date>(.-)</date>") or ""):sub(1, 10),
				message = message,
			})
		end
	end
	if #revisions == 0 then
		vim.notify("No history found", vim.log.levels.INFO)
		return
	end

	local diff_target = target
	if scope ~= "file" then
		local url = vim.system({ "svn", "info", "--show-item", "url" }, { cwd = cwd, text = true }):wait()
		diff_target = vim.trim(url.stdout or ".")
	end
	local cache = {}
	local function revision_diff(revision)
		if not cache[revision] then
			local r = vim.system({ "svn", "diff", "-c", tostring(revision), "--", diff_target }, { cwd = cwd, text = true }):wait()
			cache[revision] = r.code == 0 and r.stdout or ("svn diff failed: " .. vim.trim(r.stderr or ""))
		end
		return cache[revision]
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	local function show_whole(revision)
		local text = revision_diff(revision.revision)
		if vim.trim(text) == "" then
			vim.notify("r" .. revision.revision .. " has no textual changes here", vim.log.levels.INFO)
			return
		end
		float_text_through_delta(text)
	end

	local function pick_changed_file(revision)
		local blocks = split_diff(revision_diff(revision.revision))
		if #blocks == 0 then
			vim.notify("r" .. revision.revision .. " has no textual changes here", vim.log.levels.INFO)
			return
		end
		pickers
			.new({}, {
				prompt_title = "r" .. revision.revision .. ": " .. (revision.message:match("[^\n]*") or ""),
				sorting_strategy = "ascending", -- same layout as the revision list: first entry on top, prompt above
				layout_config = { prompt_position = "top" },
				finder = finders.new_table({
					results = blocks,
					entry_maker = function(block)
						return { value = block, display = string.format("%-2s %s", block.action, block.file), ordinal = block.file }
					end,
				}),
				sorter = conf.generic_sorter({}),
				previewer = previewers.new_buffer_previewer({
					title = "diff",
					define_preview = function(self, entry)
						vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(entry.value.text, "\n", { plain = true }))
						vim.bo[self.state.bufnr].filetype = "diff"
					end,
				}),
				attach_mappings = function(prompt_bufnr, map)
					actions.select_default:replace(function()
						local entry = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if entry then
							float_text_through_delta(entry.value.text)
						end
					end)
					map({ "i", "n" }, "<C-d>", function()
						actions.close(prompt_bufnr)
						show_whole(revision)
					end)
					return true
				end,
			})
			:find()
	end

	pickers
		.new({}, {
			prompt_title = scope == "file" and ("History of " .. vim.fs.basename(file)) or "History of the working copy",
			-- newest revision on top: results top to bottom, with the prompt above them
			sorting_strategy = "ascending",
			layout_config = { prompt_position = "top" },
			finder = finders.new_table({
				results = revisions,
				entry_maker = function(revision)
					local first_line = revision.message:match("[^\n]*") or ""
					return {
						value = revision,
						display = string.format("r%-5d %-10.10s %s  %s", revision.revision, revision.author, revision.date, first_line),
						ordinal = string.format("r%d %s %s %s", revision.revision, revision.author, revision.date, revision.message),
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				title = "message and diff",
				define_preview = function(self, entry)
					local revision = entry.value
					local lines = { string.format("r%d | %s | %s", revision.revision, revision.author, revision.date), "" }
					vim.list_extend(lines, vim.split(revision.message, "\n", { plain = true }))
					table.insert(lines, "")
					vim.list_extend(lines, vim.split(revision_diff(revision.revision), "\n", { plain = true }))
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
					vim.bo[self.state.bufnr].filetype = "diff"
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if not entry then
						return
					end
					if scope == "file" then
						show_whole(entry.value)
					else
						pick_changed_file(entry.value)
					end
				end)
				map({ "i", "n" }, "<C-d>", function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if entry then
						show_whole(entry.value)
					end
				end)
				return true
			end,
		})
		:find()
end

--- Switch the working copy to another branch, tag or trunk (`svn switch`, <leader>gS). Local changes come along;
--- you are asked first when there are any.
function M.svn_switch()
	local found = svn_targets()
	if not found then
		return
	end
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local function switch_to(target)
		local changes = vim.system({ "svn", "status", "-q" }, { cwd = found.wc_root, text = true }):wait()
		if vim.trim(changes.stdout or "") ~= "" then
			local choice = vim.fn.confirm("The working copy has local changes. They stay, but may conflict. Switch to " .. target.label .. "?", "&Yes\n&No", 2)
			if choice ~= 1 then
				return
			end
		end
		local result = vim.system({ "svn", "switch", target.url }, { cwd = found.wc_root, text = true }):wait()
		vim.cmd("checktime") -- files that changed on disk are reloaded
		if result.code ~= 0 then
			vim.notify("svn switch failed:\n" .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
			return
		end
		local conflicts = select(2, result.stdout:gsub("\n%s*C%s", "\n")) + (result.stdout:match("^%s*C%s") and 1 or 0)
		local summary = vim.trim(result.stdout):match("([^\n]*)$") -- "Updated to revision N."
		vim.notify(
			"Switched to " .. target.label .. (conflicts > 0 and (" with " .. conflicts .. " conflict(s), see svn status") or "") .. "\n" .. summary,
			conflicts > 0 and vim.log.levels.WARN or vim.log.levels.INFO
		)
	end

	pickers
		.new({}, {
			prompt_title = "Switch " .. found.relative .. " to…",
			sorting_strategy = "ascending",
			layout_config = { prompt_position = "top" },
			finder = finders.new_table({
				results = found.targets,
				entry_maker = function(target)
					return { value = target, display = target.label, ordinal = target.label }
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if entry then
						switch_to(entry.value)
					end
				end)
				return true
			end,
		})
		:find()
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Subversion conflicts, resolved with the same three-pane view as git conflicts (codediff, see lua/plugins/merge.lua).
-- codediff reads the base, ours and theirs versions from git's index, so a throwaway git repository is built for the
-- conflicted file: SVN's three leftovers (`svn info` names them) become the index stages 1, 2 and 3. When the result is
-- applied it is copied back to the real file and `svn resolve` marks the conflict as resolved.
-- ---------------------------------------------------------------------------------------------------------------------
local svn_conflicts = {} -- [temporary file] = { file = real file, ours = label, theirs = label, dir = temporary repo }

local function read_file(path)
	local handle = io.open(path, "rb")
	if not handle then
		return nil
	end
	local content = handle:read("*a")
	handle:close()
	return content
end

--- Files of the working copy with a text conflict, relative to its root.
local function svn_conflicted(root)
	local result = vim.system({ "svn", "status" }, { cwd = root, text = true }):wait()
	local files = {}
	for _, line in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
		if line:sub(1, 1) == "C" and #line > 8 then
			table.insert(files, line:sub(9))
		end
	end
	return files
end

--- Forgets a conflict session and deletes its throwaway repository (a moment later, the view may still be closing).
local function forget_svn_conflict(session)
	for key, entry in pairs(svn_conflicts) do
		if entry == session then
			svn_conflicts[key] = nil
		end
	end
	vim.defer_fn(function()
		vim.fn.delete(session.dir, "rf")
	end, 1000)
end

--- Opens the three-pane merge view for a conflicted file of a Subversion working copy.
function M.svn_open_conflict(file)
	local dir, name = vim.fs.dirname(file), vim.fs.basename(file)
	local info = vim.system({ "svn", "info", "--", name }, { cwd = dir, text = true }):wait()
	local base = (info.stdout or ""):match("Conflict Previous Base File: ([^\n]+)")
	local mine = (info.stdout or ""):match("Conflict Previous Working File: ([^\n]+)")
	local theirs = (info.stdout or ""):match("Conflict Current Base File: ([^\n]+)")
	if not (base and mine and theirs) then
		vim.notify(name .. " has no text conflict to resolve (a property or tree conflict needs `svn resolve`)", vim.log.levels.WARN)
		return
	end

	local temporary = vim.fn.tempname()
	vim.fn.mkdir(temporary, "p")
	-- git reports the real path (macOS: /var is a link to /private/var), codediff needs both to start the same way
	temporary = vim.uv.fs_realpath(temporary) or temporary
	local function git(args, stdin)
		return vim.system(vim.list_extend({ "git", "-C", temporary }, args), { text = true, stdin = stdin }):wait()
	end
	git({ "init", "-q", "." })
	local stages = {}
	for stage, leftover in ipairs({ base, mine, theirs }) do
		local content = read_file(vim.fs.joinpath(dir, leftover))
		if not content then
			vim.notify("Cannot read " .. leftover, vim.log.levels.ERROR)
			return
		end
		local hash = vim.trim(git({ "hash-object", "-w", "--stdin" }, content).stdout)
		table.insert(stages, string.format("100644 %s %d\t%s\n", hash, stage, name))
	end
	git({ "update-index", "--index-info" }, table.concat(stages))
	local temporary_file = vim.fs.joinpath(temporary, name)
	vim.fn.writefile(vim.fn.readfile(file, "b"), temporary_file, "b") -- the file with the conflict markers

	local function item(output, label)
		return vim.trim(output.stdout or "") ~= "" and vim.trim(output.stdout) or label
	end
	local here = vim.system({ "svn", "info", "--show-item", "relative-url" }, { cwd = dir, text = true }):wait()
	local session = {
		file = file,
		dir = temporary,
		ours = "working copy " .. item(here, ""),
		theirs = "incoming " .. (theirs:match("r(%d+)$") and ("r" .. theirs:match("r(%d+)$")) or ""),
	}
	svn_conflicts[temporary_file] = session
	svn_conflicts[vim.uv.fs_realpath(temporary_file) or temporary_file] = session -- /var -> /private/var on macOS
	vim.cmd("CodeDiff merge " .. vim.fn.fnameescape(temporary_file))
end

--- Labels for the two sides when the file is the result of an SVN conflict view, nil otherwise.
function M.svn_conflict_names(temporary_file)
	local session = svn_conflicts[temporary_file]
	return session and { ours = session.ours, theirs = session.theirs } or nil
end

--- Called when the merge view applies its result. For an SVN conflict: copies the result into the real file and, when
--- nothing is left unresolved, runs `svn resolve`. Returns true when the file was an SVN conflict.
function M.svn_finish_conflict(temporary_file, resolved)
	local session = svn_conflicts[temporary_file]
	if not session then
		return false
	end
	vim.fn.writefile(vim.fn.readfile(temporary_file, "b"), session.file, "b")
	if resolved then
		local result = vim.system(
			{ "svn", "resolve", "--accept", "working", "--", vim.fs.basename(session.file) },
			{ cwd = vim.fs.dirname(session.file), text = true }
		):wait()
		if result.code ~= 0 then
			vim.notify("svn resolve failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
		end
	end
	vim.cmd("checktime")
	forget_svn_conflict(session)
	return true
end

--- The merge view was closed without applying: drop the throwaway repository, opening the file again builds a new one.
function M.svn_discard_conflict(temporary_file)
	local session = svn_conflicts[temporary_file]
	if session then
		forget_svn_conflict(session)
	end
end

--- <leader>gm for Subversion: the files with a text conflict, then the merge view for the chosen one.
function M.svn_resolve_files()
	local root = svn_root()
	local files = svn_conflicted(root)
	if #files == 0 then
		vim.notify("No merge conflicts", vim.log.levels.INFO)
	elseif #files == 1 then
		M.svn_open_conflict(vim.fs.joinpath(root, files[1]))
	else
		vim.ui.select(files, { prompt = "Files with merge conflicts" }, function(file)
			if file then
				M.svn_open_conflict(vim.fs.joinpath(root, file))
			end
		end)
	end
end

--- Merge another branch, tag or trunk into the working copy (`svn merge`, <leader>gX): pick the source, see what it
--- would do, confirm, merge, and resolve the conflicts with the merge view. The result is left uncommitted.
function M.svn_merge()
	local found = svn_targets()
	if not found then
		return
	end
	local wc_root = found.wc_root
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local function counts(output)
		local result = { U = 0, A = 0, D = 0, C = 0, G = 0 }
		for _, line in ipairs(vim.split(output, "\n", { trimempty = true })) do
			local flag = line:match("^([UADCG])[ UCGM][ UCGM]?%s")
			if flag then
				result[flag] = result[flag] + 1
			end
		end
		return result
	end

	local function merge_from(target)
		local local_changes = vim.system({ "svn", "status", "-q" }, { cwd = wc_root, text = true }):wait()
		-- the folder's own property change (svn:mergeinfo of an earlier merge) shows as " M ." and is not a file change
		if vim.trim((local_changes.stdout or ""):gsub("\n? M%s+%.\n?", "\n")) ~= "" then
			local choice = vim.fn.confirm("The working copy has uncommitted changes, they will mix with the merge. Continue?", "&Yes\n&No", 2)
			if choice ~= 1 then
				return
			end
		end
		local dry = vim.system({ "svn", "merge", "--non-interactive", "--dry-run", target.url }, { cwd = wc_root, text = true }):wait()
		if dry.code ~= 0 then
			vim.notify("svn merge cannot start:\n" .. vim.trim(dry.stderr or ""), vim.log.levels.ERROR)
			return
		end
		local expected = counts(dry.stdout)
		if expected.U + expected.A + expected.D + expected.C + expected.G == 0 then
			vim.notify("Nothing to merge from " .. target.label, vim.log.levels.INFO)
			return
		end
		local summary = string.format(
			"Merge %s into %s?\n\n%d updated, %d added, %d deleted, %d merged, %d conflict(s) expected",
			target.label, found.relative, expected.U, expected.A, expected.D, expected.G, expected.C
		)
		if vim.fn.confirm(summary, "&Merge\n&Cancel", 2) ~= 1 then
			return
		end

		local result = vim.system({ "svn", "merge", "--non-interactive", target.url }, { cwd = wc_root, text = true }):wait()
		vim.cmd("checktime")
		if result.code ~= 0 then
			vim.notify("svn merge failed:\n" .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
			return
		end
		local conflicts = #svn_conflicted(wc_root)
		if conflicts == 0 then
			vim.notify("Merged " .. target.label .. ". Review it (<leader>gv) and commit when it looks right.")
			return
		end
		local choice = vim.fn.confirm(conflicts .. " file(s) have conflicts. Resolve them now?", "&Yes\n&Later", 1)
		if choice == 1 then
			M.svn_resolve_files()
		else
			vim.notify("<leader>gm opens the conflicted files", vim.log.levels.INFO)
		end
	end

	pickers
		.new({}, {
			prompt_title = "Merge into " .. found.relative .. " from…",
			sorting_strategy = "ascending",
			layout_config = { prompt_position = "top" },
			finder = finders.new_table({
				results = found.targets,
				entry_maker = function(target)
					return { value = target, display = target.label, ordinal = target.label }
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if entry then
						merge_from(entry.value)
					end
				end)
				return true
			end,
		})
		:find()
end

--- Picker over `svn status` with a diff preview. <CR> opens the file, and shows its diff when it has a BASE.
function M.svn_changes()
	local root = svn_root()
	local result = vim.system({ "svn", "status" }, { cwd = root, text = true }):wait()
	if result.code ~= 0 then
		vim.notify("svn status failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
		return
	end
	local changes = {}
	for _, line in ipairs(vim.split(result.stdout, "\n", { trimempty = true })) do
		-- the status flags take the first 7 columns, the path starts at column 9
		if #line > 8 and not line:match("^%s*>") and not line:match("^%-%-%-") then
			local flags = vim.trim(line:sub(1, 7))
			table.insert(changes, { flags = flags, file = line:sub(9), path = vim.fs.joinpath(root, line:sub(9)) })
		end
	end
	if #changes == 0 then
		vim.notify("No changes in " .. root, vim.log.levels.INFO)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	pickers
		.new({}, {
			prompt_title = "SVN changes (" .. vim.fn.fnamemodify(root, ":t") .. ")",
			finder = finders.new_table({
				results = changes,
				entry_maker = function(change)
					local display = string.format("%-3s %s", change.flags, change.file)
					return { value = change, display = display, ordinal = change.flags .. " " .. change.file }
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				title = "svn diff",
				define_preview = function(self, entry)
					local diff = vim.system({ "svn", "diff", entry.value.file }, { cwd = root, text = true }):wait()
					local text = diff.stdout ~= "" and diff.stdout or ("(no textual diff for " .. entry.value.file .. ")")
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(text, "\n", { plain = true }))
					vim.bo[self.state.bufnr].filetype = "diff"
				end,
			}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if not entry then
						return
					end
					local change = entry.value
					vim.cmd.edit(vim.fn.fnameescape(change.path))
					-- only modified, replaced and conflicted files have a BASE version to compare with
					if vim.tbl_contains({ "M", "MM", "C", "R", "RM" }, change.flags) then
						M.svn_file_diff()
					end
				end)
				return true
			end,
		})
		:find()
end

return M
