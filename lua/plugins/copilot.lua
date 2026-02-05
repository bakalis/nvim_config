return {
	{
		"zbirenbaum/copilot.lua",
		cmd = "Copilot",
		event = "InsertEnter",
		config = function()
			require("copilot").setup({
				suggestion = {
					enabled = true,
					auto_trigger = true,
					keymap = {
						accept = false,
						next = false,
						prev = false,
						dismiss = false,
					},
				},
				panel = {
					enabled = false,
				},
			})

			local suggestion = require("copilot.suggestion")

			-- SAFER real mappings
			vim.keymap.set("i", "<C-y>", suggestion.accept, { desc = "Copilot Accept" })
			vim.keymap.set("i", "<C-n>", suggestion.next, { desc = "Copilot Next" })
			vim.keymap.set("i", "<C-p>", suggestion.prev, { desc = "Copilot Prev" })
			vim.keymap.set("i", "<C-e>", suggestion.dismiss, { desc = "Copilot Dismiss" })
		end,
	},

	{
		"zbirenbaum/copilot-cmp",
		dependencies = { "zbirenbaum/copilot.lua" },
		config = function()
			require("copilot_cmp").setup()
		end,
	},
}
