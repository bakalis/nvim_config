return {
	-- Powerful Git integration for Vim
	"tpope/vim-fugitive",
	config = function()
		local vcs = require("core.vcs")
		local map = vim.keymap.set
		local opts = { noremap = true, silent = true }

		-- Git status (like mini lazygit inside Vim)
		map("n", "<leader>gs", vcs.git_only("Git"), vim.tbl_extend("force", opts, { desc = "Git Status" }))

		-- Floating Delta diff preview of the current file (Git)
		local function git_file_diff()
			local file = vim.fn.expand("%:p")
			local width = math.floor(vim.o.columns * 0.95)
			local height = math.floor(vim.o.lines * 0.95)
			local row = math.floor((vim.o.lines - height) / 2)
			local col = math.floor((vim.o.columns - width) / 2)

			-- Create a scratch buffer
			local bufnr = vim.api.nvim_create_buf(false, true) -- [listed = false, scratch = true]

			-- Open floating window
			local winid = vim.api.nvim_open_win(bufnr, true, {
				relative = "editor",
				width = width,
				height = height,
				row = row,
				col = col,
				style = "minimal",
				border = "rounded",
			})

			-- Hide line numbers
			vim.api.nvim_win_set_option(winid, "number", false)
			vim.api.nvim_win_set_option(winid, "relativenumber", false)

			-- Open terminal in the floating window running Delta diff
			vim.fn.termopen("git -c core.pager=delta diff HEAD -- " .. vim.fn.fnameescape(file), {
				on_exit = function()
					-- keep buffer open, you close manually
				end,
			})

			-- Enter terminal mode
			vim.cmd("startinsert")

			-- Map 'q' to close the floating window cleanly
			vim.api.nvim_buf_set_keymap(bufnr, "t", "q", "<C-\\><C-n>:bd!<CR>", { noremap = true, silent = true })
			vim.api.nvim_buf_set_keymap(bufnr, "n", "q", ":bd!<CR>", { noremap = true, silent = true })
		end

		-- Switch the working copy to another branch (Subversion only, git has its own tools for this)
		map("n", "<leader>gS", function()
			if vcs.require_svn() then
				vcs.svn_switch()
			end
		end, vim.tbl_extend("force", opts, { desc = "Switch svn branch" }))

		-- Merge another branch into the working copy (Subversion). Conflicts open in the merge view (<leader>gm)
		map("n", "<leader>gX", function()
			if vcs.require_svn() then
				vcs.svn_merge()
			end
		end, vim.tbl_extend("force", opts, { desc = "Merge a branch into the working copy (svn)" }))

		-- Diff of the current file: Git gets the delta float, a Subversion working copy the same float with the diff against BASE
		map("n", "<leader>gd", function()
			if vcs.kind() == "svn" then
				vcs.svn_file_diff()
			elseif vcs.require_git() then
				git_file_diff()
			end
		end, { desc = "Diff current file (git: delta, svn: against BASE, in a float)" })

		-- Merge conflict resolution lives in lua/plugins/merge.lua (<leader>gm, <leader>gM)

		-- Blame of the current file: fugitive's for git, a revision/author column for a Subversion working copy
		map("n", "<leader>gb", function()
			if vcs.kind() == "svn" then
				vcs.svn_blame()
			elseif vcs.require_git() then
				vim.cmd("Git blame")
			end
		end, vim.tbl_extend("force", opts, { desc = "Blame (git: fugitive, svn: column)" }))

		-- :GBrowse opens its URL through a :Browse command when one exists. Without it fugitive calls netrw's
		-- BrowseX with two arguments, which the netrw of Neovim 0.12 rejects (E118). vim.ui.open uses the system
		-- opener of each OS (open, xdg-open, start).
		vim.api.nvim_create_user_command("Browse", function(command)
			local _, err = vim.ui.open(command.args)
			if err then
				vim.notify("Could not open " .. command.args .. ": " .. err, vim.log.levels.ERROR)
			end
		end, { nargs = 1, desc = "Open a URL with the system browser" })

		-- Browse on GitHub (requires vim-rhubarb); a visual selection links to those lines
		-- an expr mapping, so that in visual mode the command still gets the selected range (:'<,'>GBrowse)
		map({ "n", "x" }, "<leader>go", function()
			return vcs.require_git() and ":GBrowse<CR>" or "<Esc>"
		end, vim.tbl_extend("force", opts, { expr = true, desc = "Open on the git host (selection: those lines)" }))

		map("n", "<leader>gl", vcs.git_only("G log"), vim.tbl_extend("force", opts, { desc = "Git Log" }))

		-- Open file at last commit
		map("n", "<leader>gO", vcs.git_only("Gedit HEAD~1:%"), vim.tbl_extend("force", opts, { desc = "Open file at the previous commit" }))
	end,
}
