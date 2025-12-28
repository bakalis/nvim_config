return {
	"nvim-telescope/telescope.nvim",
	event = "VimEnter",
	branch = "master",
	dependencies = {
		"nvim-lua/plenary.nvim",

		{
			"nvim-telescope/telescope-fzf-native.nvim",
			build = "make",
			cond = function()
				return vim.fn.executable("make") == 1
			end,
		},

		{ "nvim-telescope/telescope-ui-select.nvim" },

		{ "nvim-tree/nvim-web-devicons", enabled = vim.g.have_nerd_font },
	},

	config = function()
		local telescope = require("telescope")
		local builtin = require("telescope.builtin")
		local actions = require("telescope.actions")

		-- -------------------------------------------------------------------------
		-- Telescope setup
		-- -------------------------------------------------------------------------
		telescope.setup({
			defaults = {
				mappings = {
					i = {
						["<C-k>"] = actions.move_selection_previous,
						["<C-j>"] = actions.move_selection_next,
						["<C-l>"] = actions.select_default,
						["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
					},
					n = {
						["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
					},
				},
			},

			pickers = {
				find_files = {
					hidden = true,
					file_ignore_patterns = { "node_modules", "%.git", "%.venv" },
				},

				live_grep = {
					file_ignore_patterns = { "node_modules", "%.git", "%.venv" },
					additional_args = function()
						return { "--hidden" }
					end,
				},
			},

			extensions = {
				["ui-select"] = {
					require("telescope.themes").get_dropdown(),
				},
			},
		})

		-- -------------------------------------------------------------------------
		-- Extensions
		-- -------------------------------------------------------------------------
		pcall(telescope.load_extension, "fzf")
		pcall(telescope.load_extension, "ui-select")
		pcall(telescope.load_extension, "harpoon")

		-- -------------------------------------------------------------------------
		-- Standard Telescope keymaps
		-- -------------------------------------------------------------------------
		vim.keymap.set("n", "<leader>sh", builtin.help_tags, { desc = "[S]earch [H]elp" })
		vim.keymap.set("n", "<leader>sk", builtin.keymaps, { desc = "[S]earch [K]eymaps" })
		vim.keymap.set("n", "<leader>sf", builtin.find_files, { desc = "[S]earch [F]iles" })
		vim.keymap.set("n", "<leader>ss", builtin.builtin, { desc = "[S]earch [S]elect Telescope" })
		vim.keymap.set("n", "<leader>sw", builtin.grep_string, { desc = "[S]earch current [W]ord" })
		vim.keymap.set("n", "<leader>sg", builtin.live_grep, { desc = "[S]earch by [G]rep" })
		vim.keymap.set("n", "<leader>sd", builtin.diagnostics, { desc = "[S]earch [D]iagnostics" })
		vim.keymap.set("n", "<leader>sr", builtin.resume, { desc = "[S]earch [R]esume" })
		vim.keymap.set("n", "<leader>s.", builtin.oldfiles, { desc = "[S]earch Recent Files" })
		vim.keymap.set("n", "<leader><leader>", builtin.buffers, { desc = "Find existing buffers" })

		vim.keymap.set("n", "<leader>sld", builtin.lsp_definitions, { desc = "Telescope LSP Definitions" })
		vim.keymap.set("n", "<leader>slr", builtin.lsp_references, { desc = "Telescope LSP References" })
		vim.keymap.set("n", "<leader>sli", builtin.lsp_implementations, { desc = "Telescope LSP Implementations" })
		vim.keymap.set(
			"n",
			"<leader>sls",
			builtin.lsp_document_symbols,
			{ desc = "Telescope LSP Symbols (Current Buffer)" }
		)
		vim.keymap.set(
			"n",
			"<leader>slS",
			builtin.lsp_dynamic_workspace_symbols,
			{ desc = "Telescope LSP Workspace Symbols" }
		)
		vim.keymap.set("n", "<leader>sle", builtin.diagnostics, { desc = "Telescope LSP Diagnostics" })

		vim.keymap.set("n", "<leader>fh", function()
			require("telescope").extensions.harpoon.marks()
		end, { desc = "Harpoon via Telescope" })

		vim.keymap.set("n", "<leader>/", function()
			builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
				winblend = 10,
				previewer = false,
			}))
		end, { desc = "Fuzzy search in current buffer" })

		vim.keymap.set("n", "<leader>s/", function()
			builtin.live_grep({
				grep_open_files = true,
				prompt_title = "Live Grep in Open Files",
			})
		end, { desc = "Search in Open Files" })

		-- -------------------------------------------------------------------------
		-- IntelliJ-style: Find → Replace in Path (with confirmation)
		-- -------------------------------------------------------------------------
		vim.keymap.set("n", "<leader>sR", function()
			builtin.live_grep({
				prompt_title = "Search → Replace (Quickfix)",
				attach_mappings = function(_, map)
					local send_and_open_qf = function(prompt_bufnr)
						actions.send_to_qflist(prompt_bufnr)
						actions.open_qflist(prompt_bufnr)
					end

					map("i", "<CR>", send_and_open_qf)
					map("n", "<CR>", send_and_open_qf)
					return true
				end,
			})
		end, { desc = "[S]earch → [R]eplace (confirmable)" })

		vim.keymap.set("n", "<leader>sp", function()
			local pattern = vim.fn.input("File pattern (glob, e.g. *.py): ")
			pattern = pattern ~= "" and pattern or "*.*"
			require("telescope.builtin").live_grep({
				prompt_title = "Live Grep in " .. pattern,
				additional_args = function()
					return { "--glob", pattern }
				end,
			})
		end, { desc = "Search in files matching pattern" })

		-- -------------------------------------------------------------------------
		-- Optional IntelliJ-like shortcuts (macOS)
		-- -------------------------------------------------------------------------
		-- Cmd + Shift + F → Find in Path
		pcall(vim.keymap.set, "n", "<D-S-f>", "<leader>sg", { desc = "Find in Path" })

		-- Cmd + Shift + R → Replace in Path
		pcall(vim.keymap.set, "n", "<D-S-r>", "<leader>sR", { desc = "Replace in Path" })
	end,
}
