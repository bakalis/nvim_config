-- Standalone plugins with less than 10 lines of config go here
return {
	{
		-- Tmux & split window navigation
		"christoomey/vim-tmux-navigator",
	},
	{
		-- Detect tabstop and shiftwidth automatically
		"tpope/vim-sleuth",
	},
	{
		-- GitHub integration for vim-fugitive
		"tpope/vim-rhubarb",
	},
	{
		-- Hints keybinds
		"folke/which-key.nvim",
		opts = {},
		config = function(_, opts)
			require("which-key").setup(opts)

			-- Pausing after <leader> hands the key over to which-key. It gives the typed count back to the key sequence
			-- in normal mode, but not in visual mode, so `4<leader>j` on a selection lost its 4. This does the same there.
			local state = require("which-key.state")
			local execute = state.execute
			state.execute = function(current, key, node)
				local count = vim.v.count
				local visual = type(current.mode.mode) == "string" and current.mode.mode:find("x") ~= nil
				if count > 0 and visual and not (node and node.action) then
					local feedkeys = vim.api.nvim_feedkeys
					vim.api.nvim_feedkeys = function(keys, mode, escape)
						vim.api.nvim_feedkeys = feedkeys
						return feedkeys((keys:match("^%d") and "" or tostring(count)) .. keys, mode, escape)
					end
					local ok, result = pcall(execute, current, key, node)
					vim.api.nvim_feedkeys = feedkeys
					if not ok then
						error(result, 0)
					end
					return result
				end
				return execute(current, key, node)
			end
		end,
	},
	{
		-- Autoclose parentheses, brackets, quotes, etc.
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		config = true,
		opts = {},
	},
	{
		-- Highlight todo, notes, etc in comments
		"folke/todo-comments.nvim",
		event = "VimEnter",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = { signs = false },
		keys = {
			{ "<leader>st", "<cmd>TodoTelescope<cr>", desc = "[S]earch [T]odos" },
		},
	},
	{
		-- High-performance color highlighter
		"catgoose/nvim-colorizer.lua",
		event = "VeryLazy",
		opts = {},
	},
	{
		-- Surround motions: ys, ds, cs
		"kylechui/nvim-surround",
		event = "VeryLazy",
		opts = {},
	},
	{
		-- Fast jumping
		"folke/flash.nvim",
		event = "VeryLazy",
		opts = {},
		keys = {
			{
				"s",
				mode = { "n", "x", "o" },
				function()
					require("flash").jump()
				end,
				desc = "Flash",
			},
			{
				"S",
				mode = { "n", "x", "o" },
				function()
					require("flash").treesitter()
				end,
				desc = "Flash Treesitter",
			},
		},
	},
	{
		-- Diagnostics list
		"folke/trouble.nvim",
		cmd = "Trouble",
		opts = {},
		keys = {
			{ "<leader>ld", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" },
			{ "<leader>lb", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer Diagnostics (Trouble)" },
		},
	},
}
