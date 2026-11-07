return {
	"kristijanhusak/vim-dadbod-ui",
	dependencies = {
		{ "tpope/vim-dadbod", lazy = true },
		{ "kristijanhusak/vim-dadbod-completion", lazy = true },
	},
	cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer", "DBUIRenameBuffer", "DBUILastQueryInfo" },
	keys = {
		{ "<leader>Bt", "<cmd>DBUIToggle<cr>", desc = "Database: Toggle UI" },
		{ "<leader>Ba", "<cmd>DBUIAddConnection<cr>", desc = "Database: Add Connection" },
		{ "<leader>Bf", "<cmd>DBUIFindBuffer<cr>", desc = "Database: Find Query Buffer" },
	},
	init = function()
		-- libpq is keg-only in Homebrew, so psql isn't on the PATH by default
		local libpq = "/opt/homebrew/opt/libpq/bin"
		if vim.fn.isdirectory(libpq) == 1 and not vim.env.PATH:find(libpq, 1, true) then
			vim.env.PATH = libpq .. ":" .. vim.env.PATH
		end
		vim.g.db_ui_use_nerd_fonts = 1
		-- Saved connections and queries live outside the config, they can contain credentials
		vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui"
		vim.g.db_ui_execute_on_save = 0
	end,
}
