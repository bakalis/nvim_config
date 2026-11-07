return {
	{
		"nvim-neotest/neotest",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"antoinemadec/FixCursorHold.nvim",
			"nvim-treesitter/nvim-treesitter",
			"rcasia/neotest-java",
			"nvim-neotest/neotest-python",
			"nvim-neotest/neotest-go",
			"nvim-neotest/neotest-jest",
			"rouge8/neotest-rust",
		},
		config = function()
			local neotest = require("neotest")

			neotest.setup({
				adapters = {
					require("neotest-java")({}, { binaries = require("lang.java").neotest_binaries() }),

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
				-- neotest-java can't run a multi-module parent as one suite, so run each
				-- module that has tests instead ("<name> does not exist" from jdtls)
				local root = vim.fs.root(0, { "mvnw", "gradlew", ".git" }) or vim.fn.getcwd()
				local modules = {}
				for _, build_file in ipairs(vim.fs.find({ "pom.xml", "build.gradle", "build.gradle.kts" }, { path = root, limit = 50 })) do
					local dir = vim.fs.dirname(build_file)
					if dir ~= root and vim.fn.isdirectory(dir .. "/src/test") == 1 then
						modules[dir] = true
					end
				end
				local dirs = vim.tbl_keys(modules)
				if vim.bo.filetype == "java" and #dirs > 0 then
					table.sort(dirs)
					-- one after another, concurrent runs interfere with test discovery
					require("nio").run(function()
						for _, dir in ipairs(dirs) do
							neotest.run.run(dir)
						end
					end)
				else
					neotest.run.run({ suite = true })
				end
			end, { desc = "Test: All (every module)" })

			vim.keymap.set("n", "<leader>tt", function()
				neotest.run.run()
			end, { desc = "Test: Nearest" })

			vim.keymap.set("n", "<leader>td", function()
				neotest.run.run({ strategy = "dap" })
			end, { desc = "Test: Debug Nearest" })

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
