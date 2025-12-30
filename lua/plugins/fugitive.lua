return {
	-- Powerful Git integration for Vim
	"tpope/vim-fugitive",
	config = function()
		local map = vim.keymap.set
		local opts = { noremap = true, silent = true }

		-- Git status (like mini lazygit inside Vim)
		map("n", "<leader>gs", ":Git<CR>", vim.tbl_extend("force", opts, { desc = "Git Status" }))

		-- Floating Delta diff preview
		vim.keymap.set("n", "<leader>gd", function()
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

		map("n", "<leader>gb", ":Git blame<CR>", opts)

		-- Browse on GitHub (requires vim-rhubarb)
		map("n", "<leader>go", ":GBrowse<CR>", opts)

		map("n", "<leader>gl", ":G log<CR>", vim.tbl_extend("force", opts, { desc = "Git Log" }))

		-- Open file at last commit
		map("n", "<leader>gO", ":Gedit HEAD~1:%<CR>", opts)
	end,
}
