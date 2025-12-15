return {
	"Olical/conjure",
	ft = { "clojure" }, -- load only for Clojure files
	config = function()
		-- Keymap prefix for Conjure commands
		vim.g["conjure#mapping#prefix"] = "<leader>c"

		-- REPL/log window configuration (windowed style)
		vim.g["conjure#log#split"] = "horizontal"
		vim.g["conjure#log#position"] = "bottom"
		vim.g["conjure#log#height"] = 15

		-- Disable inline virtual text (results only in REPL/log window)
		vim.g["conjure#eval#inline#mode"] = "none"

		-- Highlight eval results in log (optional)
		vim.g["conjure#highlight#enabled"] = true
		vim.g["conjure#highlight#duration"] = 200

		-- Doc & definition keymaps
		vim.g["conjure#mapping#doc_word"] = "K"
		vim.g["conjure#mapping#def_word"] = "gd"

		-- Optional: automatically start insert mode in log window
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "conjure-log*",
			callback = function()
				vim.cmd("startinsert")
			end,
		})

		-- Optional: navigate evaluation outputs in log window
		vim.api.nvim_create_autocmd("BufWinEnter", {
			pattern = "conjure-log-*",
			callback = function()
				local buffer = vim.api.nvim_get_current_buf()
				-- Disable diagnostics in the REPL/log buffer
				vim.diagnostic.enable(false, { bufnr = buffer })

				-- Jump to previous/next evaluation output
				vim.keymap.set(
					{ "n", "x" },
					"[c",
					"<CMD>call search('^; -\\+$', 'bw')<CR>",
					{ silent = true, buffer = true, desc = "Jump to previous eval output" }
				)
				vim.keymap.set(
					{ "n", "x" },
					"]c",
					"<CMD>call search('^; -\\+$', 'w')<CR>",
					{ silent = true, buffer = true, desc = "Jump to next eval output" }
				)
			end,
		})

		-- Optional: auto-connect REPL when file opens (requires nREPL running)
		-- vim.cmd([[:ConjureConnect]])
	end,
}
