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
		local platform = require("core.platform")
		platform.ensure_database_clients() -- psql and mysql are often installed but not on the PATH
		vim.g.db_ui_use_nerd_fonts = 1
		-- Saved connections and queries live outside the config, they can contain credentials
		vim.g.db_ui_save_location = platform.data("db_ui")
		vim.g.db_ui_execute_on_save = 0
	end,
}
