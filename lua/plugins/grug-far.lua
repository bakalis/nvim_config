-- Project-wide search and replace in a buffer: type the search, the replacement and a file filter in one
-- window, see every result with its replacement live, then apply it to all results, one file or one line.
return {
	"MagicDuck/grug-far.nvim",
	cmd = "GrugFar",
	keys = {
		{
			"<leader>sR",
			function()
				require("grug-far").open({ transient = true })
			end,
			desc = "[S]earch and [R]eplace in project",
		},
		{
			"<leader>sR",
			function()
				require("grug-far").with_visual_selection({ transient = true })
			end,
			mode = "x",
			desc = "[S]earch and [R]eplace selection",
		},
		{
			"<leader>sW",
			function()
				require("grug-far").open({ transient = true, prefills = { search = vim.fn.expand("<cword>") } })
			end,
			desc = "Search and replace current [W]ord",
		},
		{
			"<leader>sF",
			function()
				require("grug-far").open({ transient = true, prefills = { paths = vim.fn.expand("%") } })
			end,
			desc = "Search and replace in current [F]ile",
		},
	},
	opts = {
		headerMaxWidth = 80,
	},
}
