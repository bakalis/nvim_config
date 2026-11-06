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

			-- =========================================================
			-- DAP Signs (Monokai styled)
			-- =========================================================

			-- Highlight groups
			vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#f92672", bg = bg })
			vim.api.nvim_set_hl(0, "DapBreakpointCondition", { fg = "#e6db74", bg = bg })
			vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#ae81ff", bg = bg })
			vim.api.nvim_set_hl(0, "DapStopped", { fg = "#66d9ef", bg = bg, bold = true })

			-- Signs
			vim.fn.sign_define("DapBreakpoint", {
				text = "●",
				texthl = "DapBreakpoint",
				linehl = "",
				numhl = "",
			})

			vim.fn.sign_define("DapBreakpointCondition", {
				text = "◆",
				texthl = "DapBreakpointCondition",
				linehl = "",
				numhl = "",
			})

			vim.fn.sign_define("DapLogPoint", {
				text = "◆",
				texthl = "DapLogPoint",
				linehl = "",
				numhl = "",
			})

			vim.api.nvim_set_hl(0, "DapStoppedLine", {
				bg = "#2d344a",
			})

			vim.api.nvim_set_hl(0, "CursorLine", {
				bg = "#292e42",
			})

			vim.fn.sign_define("DapStopped", {
				text = "▶",
				texthl = "DapStopped",
				linehl = "DapStoppedLine",
				numhl = "",
			})
		end,
	},
}
