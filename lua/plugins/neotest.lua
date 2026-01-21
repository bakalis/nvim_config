return {
	{
		"nvim-neotest/neotest",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"antoinemadec/FixCursorHold.nvim",
			"nvim-treesitter/nvim-treesitter",
			"nvim-neotest/neotest-python",
			"nvim-neotest/neotest-go",
			"nvim-neotest/neotest-jest",
			"rouge8/neotest-rust",
		},
		config = function()
			local neotest = require("neotest")

			neotest.setup({
				adapters = {
					require("neotest-python")({
						runner = "pytest",
					}),

					require("neotest-go")({}),

					require("neotest-jest")({
						jestCommand = "npm test --",
					}),

					require("neotest-rust")({
						args = { "--no-capture" },
						dap_adapter = "lldb",
					}),
				},
			})

			vim.keymap.set("n", "<leader>tf", function()
				neotest.run.run(vim.fn.expand("%"))
			end, { desc = "Test: File" })

			vim.keymap.set("n", "<leader>ta", function()
				neotest.run.run({ suite = true })
			end, { desc = "Test: All" })

			vim.keymap.set("n", "<leader>tl", function()
				neotest.run.run_last()
			end, { desc = "Test: Last" })

			vim.keymap.set("n", "<leader>ts", function()
				neotest.summary.toggle()
			end, { desc = "Test: Summary" })

			vim.keymap.set("n", "<leader>tO", function()
				neotest.output.open({ enter = true, short = true })
			end, { desc = "Test: Output (float)" })

			vim.keymap.set("n", "<leader>tS", function()
				neotest.run.stop()
			end, { desc = "Test: Stop" })
		end,
	},
}
