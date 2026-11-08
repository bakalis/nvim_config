-- Merge conflict resolution
--   * codediff.nvim: three pane merge view (incoming | result | current), per block accept, like
--     IntelliJ's merge dialog. Also the tool behind `git mergetool`
--   * resolve.nvim: highlighting, jumping and choosing sides directly in files with conflict markers
local platform = require("core.platform")
local merge_root -- repository of the file being resolved, set by the keys below

-- Pick a branch (fuzzy, local and remote) in a popup and run `:CodeDiff HEAD <branch>`
local function diff_with_branch()
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local root = vim.fs.root(0, ".git") or vim.fn.getcwd()
	require("telescope.builtin").git_branches({
		cwd = root,
		show_remote_tracking_branches = true,
		prompt_title = "CodeDiff HEAD against…",
		attach_mappings = function(prompt_bufnr)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				if selection then
					vim.cmd("CodeDiff HEAD " .. selection.value)
				end
			end)
			return true
		end,
	})
end

local function git(root, ...)
	local result = vim.system(vim.list_extend({ "git", "-C", root }, { ... }), { text = true }):wait()
	return result.code == 0 and vim.trim(result.stdout or "") or nil
end

local function read_first_line(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local line = file:read("*l")
	file:close()
	return line
end

local function ref_name(root, rev)
	local name =
		git(root, "name-rev", "--name-only", "--no-undefined", "--refs=refs/heads/*", "--refs=refs/remotes/*", rev)
	return name and name:gsub("^remotes/", ""):gsub("[~^]%d*$", "") or git(root, "rev-parse", "--short", rev) or rev
end

-- Names for the two sides of the conflict being resolved, git's ours/theirs depend on the operation
local function side_names(root)
	local git_dir = git(root, "rev-parse", "--absolute-git-dir")
	if not git_dir then
		return nil
	end
	for _, dir in ipairs({ "rebase-merge", "rebase-apply" }) do
		if vim.fn.isdirectory(platform.join(git_dir, dir)) == 1 then
			local onto = read_first_line(platform.join(git_dir, dir, "onto"))
			local head = read_first_line(platform.join(git_dir, dir, "head-name"))
			return {
				ours = (onto and ref_name(root, onto) or "?") .. " (rebase onto)",
				theirs = (head and head:gsub("^refs/heads/", "") or "?") .. " (your commits)",
			}
		end
	end
	local current = git(root, "branch", "--show-current")
	local ours = current ~= "" and current or git(root, "rev-parse", "--short", "HEAD")
	if vim.uv.fs_stat(platform.join(git_dir, "MERGE_HEAD")) then
		local message = read_first_line(platform.join(git_dir, "MERGE_MSG")) or ""
		local theirs = message:match("^Merge remote%-tracking branch '([^']+)'")
			or message:match("^Merge branch '([^']+)'")
			or message:match("^Merge tag '([^']+)'")
			or ref_name(root, "MERGE_HEAD")
		return { ours = ours, theirs = theirs }
	end
	if vim.uv.fs_stat(platform.join(git_dir, "CHERRY_PICK_HEAD")) then
		local picked = git(root, "log", "-1", "--format=%h %s", "CHERRY_PICK_HEAD")
		return { ours = ours, theirs = "cherry-pick " .. (picked or "") }
	end
	return nil
end

-- codediff's accept actions only work with the cursor in the left or right pane. These do the same
-- from the Result pane, so you can stay there: the block under the cursor gets replaced by
-- yours (left), theirs (right), both, or the base. They also work on a block resolved earlier.
-- (Uses codediff internals, check this if the plugin changes its conflict code.)
local result_keys = {} -- tabpage -> result buffer that got the keys

local function resolve_in_result(tabpage, choice)
	local lifecycle = require("codediff.ui.lifecycle")
	local tracking = require("codediff.ui.conflict.tracking")
	local session = lifecycle.get_session(tabpage)
	if not (session and session.result_bufnr and session.conflict_blocks) then
		return
	end

	local line = vim.api.nvim_win_get_cursor(0)[1]
	local block
	for _, candidate in ipairs(session.conflict_blocks) do
		local mark = candidate.extmark_id
			and vim.api.nvim_buf_get_extmark_by_id(
				session.result_bufnr,
				tracking.tracking_ns,
				candidate.extmark_id,
				{ details = true }
			)
		if mark and #mark > 0 then
			local first = mark[1] + 1
			local last = mark[3] and mark[3].end_row and (mark[3].end_row + 1) or first
			if line >= first and line <= last then
				block = candidate
				break
			end
		end
	end
	if not block then
		vim.notify("No conflict at the cursor", vim.log.levels.INFO)
		return
	end

	local ours = tracking.get_lines_for_range(
		session.original_bufnr,
		block.output1_range.start_line,
		block.output1_range.end_line
	)
	local theirs = tracking.get_lines_for_range(
		session.modified_bufnr,
		block.output2_range.start_line,
		block.output2_range.end_line
	)
	local lines
	if choice == "ours" then
		lines = ours
	elseif choice == "theirs" then
		lines = theirs
	elseif choice == "both" then
		local combine = require("codediff.ui.conflict.resolution.combine")
		lines = combine.smart_combine_inputs(session, block, 1) or combine.dumb_combine_inputs(ours, theirs, 1)
	else
		local base = session.merge_base_lines or session.result_base_lines
		lines = {}
		for i = block.base_range.start_line, block.base_range.end_line - 1 do
			table.insert(lines, base[i] or "")
		end
	end

	require("codediff.ui.conflict.resolution.replace").apply_to_result(
		session.result_bufnr,
		block,
		lines,
		session.result_base_lines
	)
	require("codediff.ui.conflict.gutter").refresh(session)
	require("codediff.ui.refresh").refresh_result_now(session.result_bufnr)
end

-- Finish or leave a merge view without quitting Neovim. Views started by `git mergetool` are
-- left alone: those have to exit Neovim so that git can continue.
local function current_merge()
	local tabpage = vim.api.nvim_get_current_tabpage()
	local session = require("codediff.ui.lifecycle").get_session(tabpage)
	if not (session and session.result_bufnr and session.conflict_blocks) then
		vim.notify("Not in a merge view", vim.log.levels.WARN)
		return
	end
	return tabpage, session
end

local function merge_close()
	local tabpage = current_merge()
	if tabpage then
		require("codediff.ui.lifecycle").close(tabpage)
	end
end

-- Like IntelliJ's "Apply": write the result, mark the file resolved (git add) and close the view
local function merge_apply()
	local tabpage, session = current_merge()
	if not tabpage then
		return
	end

	local tracking = require("codediff.ui.conflict.tracking")
	local unresolved = 0
	for _, block in ipairs(session.conflict_blocks) do
		if tracking.is_block_active(session, block) then
			unresolved = unresolved + 1
		end
	end
	if unresolved > 0 then
		local choice =
			vim.fn.confirm(unresolved .. " conflict(s) not resolved yet. Save the result anyway?", "&Yes\n&No", 2)
		if choice ~= 1 then
			return
		end
	end

	local file = vim.api.nvim_buf_get_name(session.result_bufnr)
	vim.api.nvim_buf_call(session.result_bufnr, function()
		vim.cmd("silent write")
	end)
	if unresolved == 0 then
		local root = vim.fs.root(file, ".git") or vim.fn.getcwd()
		local result = vim.system({ "git", "-C", root, "add", "--", file }, { text = true }):wait()
		if result.code ~= 0 then
			vim.notify("git add failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
		end
	end
	local name = vim.fn.fnamemodify(file, ":t")
	require("codediff.ui.lifecycle").close(tabpage)
	vim.notify(unresolved == 0 and (name .. " resolved and staged") or (name .. " saved with unresolved conflicts"))
end

local function attach_result_keys(tabpage, tries)
	local session = require("codediff.ui.lifecycle").get_session(tabpage)
	local buf = session and session.result_bufnr
	-- wait until codediff has bound its own keys here, ours have to come after
	local ready = buf
		and vim.api.nvim_buf_is_valid(buf)
		and vim.api.nvim_buf_call(buf, function()
			return vim.fn.maparg("]x", "n") ~= ""
		end)
	if not ready then
		if (tries or 40) > 0 then
			vim.defer_fn(function()
				attach_result_keys(tabpage, (tries or 40) - 1)
			end, 100)
		end
		return
	end
	local function map(lhs, choice, desc)
		vim.keymap.set("n", lhs, function()
			resolve_in_result(tabpage, choice)
		end, { buffer = buf, silent = true, nowait = true, desc = desc })
	end
	-- finish keys on all three panes
	for _, pane in ipairs({ session.original_bufnr, session.modified_bufnr, buf }) do
		if pane and vim.api.nvim_buf_is_valid(pane) then
			vim.keymap.set(
				"n",
				"<leader>ma",
				merge_apply,
				{ buffer = pane, silent = true, desc = "Merge: apply (save, stage, close)" }
			)
			vim.keymap.set("n", "<leader>mc", merge_close, { buffer = pane, silent = true, desc = "Merge: close view" })
		end
	end
	map("<leader>co", "ours", "Accept ours (left) into result")
	map("<leader>ct", "theirs", "Accept theirs (right) into result")
	map("<leader>cb", "both", "Accept both into result")
	map("<leader>cx", "base", "Discard both, keep base")
	result_keys[tabpage] = { buf, session.original_bufnr, session.modified_bufnr }
end

local function detach_result_keys(tabpage)
	local bufs = result_keys[tabpage]
	result_keys[tabpage] = nil
	for index, buf in ipairs(bufs or {}) do
		if buf and vim.api.nvim_buf_is_valid(buf) then
			local keys = { "<leader>ma", "<leader>mc" }
			if index == 1 then
				vim.list_extend(keys, { "<leader>co", "<leader>ct", "<leader>cb", "<leader>cx" })
			end
			for _, lhs in ipairs(keys) do
				pcall(vim.keymap.del, "n", lhs, { buffer = buf })
			end
		end
	end
end

-- codediff sets fixed "Ours (Current)" / "Theirs (Incoming)" titles when the view opens
local function retitle(tabpage, tries)
	local names = side_names(merge_root or vim.fn.getcwd())
	if not names then
		return
	end
	local function apply()
		local found = false
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			local winbar = vim.wo[win].winbar
			if winbar == " Ours (Current)" then
				vim.wo[win].winbar = " Ours (Current) · " .. names.ours
				found = true
			elseif winbar == " Theirs (Incoming)" then
				vim.wo[win].winbar = " Theirs (Incoming) · " .. names.theirs
				found = true
			end
		end
		return found
	end
	-- the view builds its windows asynchronously, wait for them
	local function attempt(remaining)
		if not apply() and remaining > 0 then
			vim.defer_fn(function()
				attempt(remaining - 1)
			end, 100)
		end
	end
	attempt(tries or 30)
end

return {
	{
		"esmuellert/codediff.nvim",
		cmd = "CodeDiff",
		config = function(_, opts)
			require("codediff").setup(opts)
			vim.api.nvim_create_user_command(
				"MergeApply",
				merge_apply,
				{ desc = "Save the merge result, git add it and close the merge view" }
			)
			vim.api.nvim_create_user_command(
				"MergeClose",
				merge_close,
				{ desc = "Close the merge view without quitting Neovim" }
			)
			vim.api.nvim_create_autocmd("User", {
				group = vim.api.nvim_create_augroup("codediff-branch-titles", { clear = true }),
				pattern = "CodeDiffOpen",
				callback = function(event)
					local tabpage = event.data and event.data.tabpage or vim.api.nvim_get_current_tabpage()
					retitle(tabpage)
					attach_result_keys(tabpage)
				end,
			})
			vim.api.nvim_create_autocmd("User", {
				group = vim.api.nvim_create_augroup("codediff-result-keys", { clear = true }),
				pattern = "CodeDiffClose",
				callback = function(event)
					detach_result_keys(event.data and event.data.tabpage or vim.api.nvim_get_current_tabpage())
				end,
			})
		end,
		keys = {
			{
				"<leader>gm",
				function()
					local root = vim.fs.root(0, ".git") or vim.fn.getcwd()
					merge_root = root
					local result = vim.system(
						{ "git", "diff", "--name-only", "--diff-filter=U" },
						{ cwd = root, text = true }
					)
						:wait()
					local files = vim.split(vim.trim(result.stdout or ""), "\n", { trimempty = true })
					if #files == 0 then
						vim.notify("No merge conflicts", vim.log.levels.INFO)
					elseif #files == 1 then
						vim.cmd("CodeDiff merge " .. vim.fn.fnameescape(platform.join(root, files[1])))
					else
						vim.ui.select(files, { prompt = "Files with merge conflicts" }, function(file)
							if file then
								vim.cmd("CodeDiff merge " .. vim.fn.fnameescape(platform.join(root, file)))
							end
						end)
					end
				end,
				desc = "Merge: Resolve Conflicted Files",
			},
			-- Changes view (working tree, like IntelliJ's commit window); the same key closes it again
			{ "<leader>gv", "<cmd>CodeDiff<cr>", desc = "Diff: Changed Files" },
			{ "<leader>gh", "<cmd>CodeDiff history %<cr>", desc = "Diff: History of Current File" },
			{ "<leader>gB", diff_with_branch, desc = "Diff: HEAD against a Branch (popup)" },
			{ "<leader>gH", "<cmd>CodeDiff history<cr>", desc = "Diff: Repository History" },
			{
				"<leader>gM",
				function()
					merge_root = vim.fs.root(0, ".git") or vim.fn.getcwd()
					vim.cmd("CodeDiff merge %")
				end,
				desc = "Merge: Resolve Current File",
			},
		},
		opts = {
			diff = {
				conflict_result_position = "center", -- result between the two sides
				conflict_ours_position = "left", -- left is yours (current branch), right is theirs
			},
			keymaps = {
				-- codediff's "incoming" always means the left pane and "current" the right pane, whatever
				-- conflict_ours_position says. Yours is on the left, so swap the keys to make
				-- co = yours (left, "Ours (Current)") and ct = theirs (right, "Theirs (Incoming)")
				conflict = {
					accept_incoming = "<leader>co",
					accept_current = "<leader>ct",
					accept_all_incoming = "<leader>cO",
					accept_all_current = "<leader>cT",
				},
			},
		},
	},
	{
		"spacedentist/resolve.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {},
	},
}
