return {
	{
		"tanvirtin/monokai.nvim", -- or your monokai variant
		name = "monokai",
		lazy = false,
		priority = 1000,
		config = function()
			vim.cmd("colorscheme monokai") -- Monokai for syntax

			local bg = "#1a1b26" -- TokyoNight dark background
			local sidebar_bg = "#16161e"
			local float_bg = "#1f2335"

			-- Core background overrides
			vim.api.nvim_set_hl(0, "Normal", { bg = bg })
			vim.api.nvim_set_hl(0, "NormalNC", { bg = bg })
			vim.api.nvim_set_hl(0, "SignColumn", { bg = bg })
			vim.api.nvim_set_hl(0, "VertSplit", { bg = sidebar_bg })
			vim.api.nvim_set_hl(0, "StatusLine", { bg = sidebar_bg })
			vim.api.nvim_set_hl(0, "TabLineFill", { bg = sidebar_bg })
			vim.api.nvim_set_hl(0, "MsgArea", { bg = bg })
			vim.api.nvim_set_hl(0, "CursorLine", { bg = "#292e42" })

			-- Floating windows
			vim.api.nvim_set_hl(0, "NormalFloat", { bg = float_bg })
			vim.api.nvim_set_hl(0, "FloatBorder", { bg = float_bg })

			-- NvimTree tweaks
			vim.api.nvim_set_hl(0, "NvimTreeNormal", { bg = sidebar_bg })
			vim.api.nvim_set_hl(0, "NvimTreeNormalNC", { bg = sidebar_bg })
			vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { bg = sidebar_bg })
			vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { fg = bg, bg = bg })

			-- Optional: override some icon highlights (example)
			vim.api.nvim_set_hl(0, "NvimTreeFolderIcon", { fg = "#7aa2f7", bg = sidebar_bg }) -- TokyoNight blue

			-- Add more DevIcons or plugin-specific groups here if needed
		end,
	},
}
