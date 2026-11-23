return {
	"kdheepak/lazygit.nvim",
	cmd = {
		"LazyGit",
		"LazyGitConfig",
		"LazyGitCurrentFile",
		"LazyGitFilter",
		"LazyGitFilterCurrentFile",
	},
	-- optional for floating window border decoration
	dependencies = {
		"nvim-lua/plenary.nvim",
	},
	-- setting the keybinding for LazyGit with 'keys' is recommended in
	-- order to load the plugin when the command is run for the first time
	keys = {
		{ "<leader>lg", "<cmd>LazyGit<cr>", desc = "Open lazy git" },
		{ "<leader>ls", "<cmd>LazySvn<cr>", desc = "Open lazysvn (Subversion)" },
	},
	init = function()
		require("core.platform").use_lazygit_config()
		-- Subversion counterpart: lazysvn in a floating terminal, started in the working copy's root
		vim.api.nvim_create_user_command("LazySvn", function()
			require("core.tui").open("lazysvn", {
				title = "LazySVN",
				marker = ".svn",
				install = "see https://lazysvn.pages.dev for the install options",
			})
		end, { desc = "Open lazysvn in a floating terminal" })
	end,
}
