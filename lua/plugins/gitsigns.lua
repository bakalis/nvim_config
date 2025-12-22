return {
	"lewis6991/gitsigns.nvim",
	opts = {
		signs = {
			add = { text = "+" },
			change = { text = "~" },
			delete = { text = "_" },
			topdelete = { text = "‾" },
			changedelete = { text = "~" },
		},
		signs_staged = {
			add = { text = "+" },
			change = { text = "~" },
			delete = { text = "_" },
			topdelete = { text = "‾" },
			changedelete = { text = "~" },
		},
		current_line_blame = false, -- optional
		on_attach = function(bufnr)
			local gs = package.loaded.gitsigns

			local opts = { buffer = bufnr, noremap = true, silent = true }

			-- Navigate hunks
			vim.keymap.set("n", "]h", gs.next_hunk, opts)
			vim.keymap.set("n", "[h", gs.prev_hunk, opts)

			-- Preview hunk
			vim.keymap.set("n", "<leader>hp", gs.preview_hunk, vim.tbl_extend("force", opts, { desc = "Preview Hunk" }))

			-- Stage/undo stage hunk
			vim.keymap.set("n", "<leader>hs", gs.stage_hunk, vim.tbl_extend("force", opts, { desc = "Stage Hunk" }))
			vim.keymap.set(
				"n",
				"<leader>hu",
				gs.undo_stage_hunk,
				vim.tbl_extend("force", opts, { desc = "Undo Stage Hunk" })
			)

			-- Diff current buffer against HEAD
			vim.keymap.set("n", "<leader>gd", gs.diffthis, opts)
			vim.keymap.set("n", "<leader>gD", function()
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					if vim.wo[win].diff then
						vim.api.nvim_win_close(win, true)
					end
				end
			end, { noremap = true, silent = true })
		end,
	},
}
