return {
	-- Powerful Git integration for Vim
	"tpope/vim-fugitive",
	config = function()
		local map = vim.keymap.set
		local opts = { noremap = true, silent = true }

		-- Git status (like mini lazygit inside Vim)
		map("n", "<leader>gs", ":Git<CR>", vim.tbl_extend("force", opts, { desc = "Git Status" }))

		-- Diff current file vs HEAD
		map("n", "<leader>gd", ":Gvdiffsplit<CR>", opts)

		-- Blame current file
		map("n", "<leader>gb", ":Git blame<CR>", opts)

		-- Browse on GitHub (requires vim-rhubarb)
		map("n", "<leader>go", ":GBrowse<CR>", opts)

		map("n", "<leader>gl", ":G log<CR>", vim.tbl_extend("force", opts, { desc = "Git Log" }))

		-- Open file at last commit
		map("n", "<leader>gO", ":Gedit HEAD~1:%<CR>", opts)

		vim.keymap.set("n", "<leader>gq", function()
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				if vim.wo[win].diff then
					vim.api.nvim_win_close(win, true)
				end
			end
		end, { noremap = true, silent = true })
	end,
}
