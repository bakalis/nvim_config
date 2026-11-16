local function cargo(action)
	return function()
		require("lang.cargo")[action]()
	end
end

return {
	{
		-- rust-analyzer client and its extras (macro expansion, hover actions, debugging the test under the
		-- cursor, neotest adapter). Starts by itself in Rust buffers, configured through vim.g.rustaceanvim:
		-- see lua/lang/rust.lua
		"mrcjkb/rustaceanvim",
		lazy = false,
		init = function()
			vim.g.rustaceanvim = function()
				return require("lang.rust").config()
			end
		end,
		keys = {
			{ "<leader>Cb", cargo("build"), desc = "Cargo: Build" },
			{ "<leader>Cr", cargo("run"), desc = "Cargo: Run" },
			{ "<leader>Cc", cargo("check"), desc = "Cargo: Check" },
			{ "<leader>Cl", cargo("clippy"), desc = "Cargo: Clippy" },
			{ "<leader>Ct", cargo("test"), desc = "Cargo: Test" },
			{ "<leader>Cd", cargo("doc"), desc = "Cargo: Build and open the docs" },
			{ "<leader>Cx", cargo("exec"), desc = "Cargo: Execute a command" },
			{ "<leader>Co", cargo("toggle_output"), desc = "Cargo: Show / hide output" },
			{ "<leader>Cq", cargo("toggle_quickfix"), desc = "Cargo: Errors and warnings (quickfix)" },
			{ "<leader>CR", cargo("toggle_release"), desc = "Cargo: Toggle release profile (--release)" },
			{ "<leader>CF", cargo("select_features"), desc = "Cargo: Features" },
			{ "<leader>CP", cargo("select_package"), desc = "Cargo: Workspace package" },
		},
	},
	{
		-- Cargo.toml: versions, features and upgrades of the dependencies
		"saecki/crates.nvim",
		event = { "BufRead Cargo.toml" },
		opts = {
			-- completion, hover and code actions through an in-process language server
			lsp = {
				enabled = true,
				actions = true,
				completion = true,
				hover = true,
				on_attach = function(_, bufnr)
					local crates = require("crates")
					local map = function(keys, func, desc)
						vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "Crates: " .. desc })
					end
					map("<leader>Cv", crates.show_versions_popup, "Versions")
					map("<leader>Cf", crates.show_features_popup, "Features")
					map("<leader>CD", crates.show_dependencies_popup, "Dependencies")
					map("<leader>Cu", crates.upgrade_crate, "Upgrade Crate")
					map("<leader>CU", crates.upgrade_all_crates, "Upgrade All Crates")
					map("<leader>Ci", crates.open_crates_io, "Open crates.io")
				end,
			},
		},
	},
}
