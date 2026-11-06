return {
	{
		"stevearc/conform.nvim",
		event = "BufWritePre",
		cmd = "ConformInfo",
		opts = {
			formatters_by_ft = {
				lua = { "stylua" },
				python = { "ruff_organize_imports", "ruff_format" },
				sh = { "shfmt" },
				bash = { "shfmt" },
				terraform = { "terraform_fmt" },
				haskell = { "ormolu" },
				html = { "prettier" },
				json = { "prettier" },
				yaml = { "prettier" },
				markdown = { "prettier" },
			},
			formatters = {
				shfmt = { prepend_args = { "-i", "4" } },
			},
			format_on_save = function(bufnr)
				-- Java only formats on save with an Eclipse formatter profile (lua/lang/java.lua),
				-- otherwise jdtls would reformat whole files in its default style
				if vim.bo[bufnr].filetype == "java" and not vim.b[bufnr].java_format_on_save then
					return
				end
				return { timeout_ms = 2000, lsp_format = "fallback" }
			end,
		},
	},
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPost", "BufWritePost", "BufNewFile" },
		config = function()
			local lint = require("lint")
			lint.linters_by_ft = {
				make = { "checkmake" },
				javascript = { "eslint_d" },
				typescript = { "eslint_d" },
				javascriptreact = { "eslint_d" },
				typescriptreact = { "eslint_d" },
			}
			vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
				group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
				callback = function()
					lint.try_lint()
				end,
			})
		end,
	},
}
