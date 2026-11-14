local parsers = {
	"lua", "clojure", "haskell", "rust", "python", "javascript", "typescript", "vimdoc", "vim", "regex",
	"terraform", "sql", "dockerfile", "toml", "json", "java", "groovy", "go", "gitignore",
	"graphql", "yaml", "make", "cmake", "markdown", "markdown_inline", "bash", "tsx", "css", "html", "xml",
}

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			local ts = require("nvim-treesitter")
			ts.setup()
			-- Needs the `tree-sitter` CLI (installed through mason-tool-installer in lsp.lua)
			if require("core.platform").has("tree-sitter") then
				ts.install(parsers)
			end

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("treesitter-start", { clear = true }),
				callback = function(ev)
					if ev.match == "csv" then
						return
					end
					local lang = vim.treesitter.language.get_lang(ev.match)
					if not lang then
						return
					end
					local installed = vim.list_contains(ts.get_installed(), lang)
					if not installed and not vim.list_contains(ts.get_available(), lang) then
						return -- no parser exists for this filetype (neo-tree, fidget, ...)
					end
					if require("core.platform").has("tree-sitter") and not installed then
						ts.install({ lang }):await(function()
							if vim.api.nvim_buf_is_valid(ev.buf) then
								pcall(vim.treesitter.start, ev.buf, lang)
							end
						end)
						return
					end
					if pcall(vim.treesitter.start, ev.buf, lang) and ev.match ~= "ruby" then
						vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		config = function()
			require("nvim-treesitter-textobjects").setup({
				select = { lookahead = true },
				move = { set_jumps = true }, -- the jumps are added to the jumplist, <C-o> goes back
			})
			local select = require("nvim-treesitter-textobjects.select").select_textobject
			for key, query in pairs({
				af = "@function.outer",
				["if"] = "@function.inner",
				ac = "@class.outer",
				ic = "@class.inner",
				aa = "@parameter.outer",
				ia = "@parameter.inner",
			}) do
				vim.keymap.set({ "x", "o" }, key, function()
					select(query, "textobjects")
				end, { desc = "TS textobject " .. query })
			end

			-- Moving between functions: ]f / [f to the start of the next / previous one, ]F / [F to their ends
			local move = require("nvim-treesitter-textobjects.move")
			for key, motion in pairs({
				["]f"] = { move.goto_next_start, "Next function start" },
				["[f"] = { move.goto_previous_start, "Previous function start" },
				["]F"] = { move.goto_next_end, "Next function end" },
				["[F"] = { move.goto_previous_end, "Previous function end" },
			}) do
				vim.keymap.set({ "n", "x", "o" }, key, function()
					motion[1]("@function.outer", "textobjects")
				end, { desc = motion[2] })
			end
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-context",
		event = "VeryLazy",
		opts = { max_lines = 3 },
	},
}
