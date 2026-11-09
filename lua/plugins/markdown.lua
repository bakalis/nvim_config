-- Markdown rendered inside the buffer (headings, code blocks, tables, checkboxes, callouts).
-- The text stays editable; the line under the cursor is shown raw in normal/command mode.
return {
	"MeanderingProgrammer/render-markdown.nvim",
	dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
	ft = { "markdown" },
	---@module 'render-markdown'
	---@type render.md.UserConfig
	opts = {
		file_types = { "markdown" },
		completions = { blink = { enabled = true } },
	},
	keys = {
		{ "<leader>tm", "<cmd>RenderMarkdown buf_toggle<cr>", desc = "Toggle Markdown rendering" },
	},
}
