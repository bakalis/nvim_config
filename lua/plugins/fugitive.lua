return {
	-- Powerful Git integration for Vim
	"tpope/vim-fugitive",
	config = function()
		local map = vim.keymap.set
		local opts = { noremap = true, silent = true }

		-- Git status (like mini lazygit inside Vim)
		map("n", "<leader>gs", ":Git<CR>", vim.tbl_extend("force", opts, { desc = "Git Status" }))

		-- Floating Delta diff preview
		map("n", "<leader>gd", function()
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
		end, { desc = "Delta diff (floating current file)" })

		-- Merge conflict resolution lives in lua/plugins/merge.lua (<leader>gm, <leader>gM)

		map("n", "<leader>gb", ":Git blame<CR>", opts)

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
		map({ "n", "x" }, "<leader>go", ":GBrowse<CR>", opts)

		map("n", "<leader>gl", ":G log<CR>", vim.tbl_extend("force", opts, { desc = "Git Log" }))

		-- Open file at last commit
		map("n", "<leader>gO", ":Gedit HEAD~1:%<CR>", opts)
	end,
}
