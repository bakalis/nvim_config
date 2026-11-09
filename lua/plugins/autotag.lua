-- HTML / XML tags: typing <div> adds </div>, and renaming one tag renames its partner.
return {
	"windwp/nvim-ts-autotag",
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	event = { "BufReadPre", "BufNewFile" },
	opts = {
		opts = {
			enable_close = true, -- <div> becomes <div></div>
			enable_rename = true, -- editing a tag name edits the closing one
			enable_close_on_slash = true, -- typing </ completes the closing tag
		},
	},
}
