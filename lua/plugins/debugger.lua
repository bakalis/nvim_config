return {
	"mfussenegger/nvim-dap",
	dependencies = {
		"williamboman/mason.nvim",
		"jay-babu/mason-nvim-dap.nvim",
		{
			"rcarriga/nvim-dap-ui",
			dependencies = { "nvim-neotest/nvim-nio" },
		},
		"theHamsta/nvim-dap-virtual-text",
	},
	config = function()
		local dap = require("dap")
		local dapui = require("dapui")

		-- Ensure Mason is ready
		require("mason").setup()

		-- Load language-specific configurations
		local lang_configs = {
			rust = "dap.dap_rust",
			python = "dap.dap_python",
			-- Add more languages here:
			-- go = "dap.dap_go",
			-- javascript = "dap.dap_javascript",
		}

		local handlers = {}
		local ensure_installed = {}

		-- Load each language configuration
		for lang, module_path in pairs(lang_configs) do
			local ok, lang_module = pcall(require, module_path)
			if ok then
				-- Collect adapters to install
				if lang_module.adapters then
					for _, adapter in ipairs(lang_module.adapters) do
						table.insert(ensure_installed, adapter)
					end
				end

				-- Collect handlers
				if lang_module.setup_handler then
					handlers[lang_module.adapter_name] = function(config)
						require("mason-nvim-dap").default_setup(config)
						lang_module.setup_handler(dap)
					end
				end
			else
				vim.notify(
					string.format("Failed to load DAP config for %s: %s", lang, lang_module),
					vim.log.levels.WARN
				)
			end
		end

		-- Default handler for any other adapters
		handlers[1] = function(config)
			require("mason-nvim-dap").default_setup(config)
		end

		-- Mason-nvim-dap setup
		require("mason-nvim-dap").setup({
			ensure_installed = ensure_installed,
			automatic_installation = true,
			handlers = handlers,
		})

		-- DAP UI
		dapui.setup({
			layouts = {
				{
					elements = {
						{ id = "scopes", size = 0.25 },
						{ id = "breakpoints", size = 0.25 },
						{ id = "stacks", size = 0.25 },
						{ id = "watches", size = 0.25 },
					},
					size = 40,
					position = "left",
				},
				{
					elements = {
						{ id = "repl", size = 0.5 },
						{ id = "console", size = 0.5 },
					},
					size = 10,
					position = "bottom",
				},
			},
		})

		require("nvim-dap-virtual-text").setup({ commented = true })

		-- Auto open/close UI
		dap.listeners.after.event_initialized["dapui"] = function()
			dapui.open()
		end
		dap.listeners.before.event_terminated["dapui"] = function()
			dapui.close()
		end
		dap.listeners.before.event_exited["dapui"] = function()
			dapui.close()
		end

		-- Keymaps
		local map = vim.keymap.set
		local opts = { silent = true }
		map("n", "<leader>dc", dap.continue, vim.tbl_extend("force", opts, { desc = "DAP Continue" }))
		map("n", "<leader>db", dap.toggle_breakpoint, vim.tbl_extend("force", opts, { desc = "DAP Breakpoint" }))
		map("n", "<leader>di", dap.step_into, vim.tbl_extend("force", opts, { desc = "DAP Step Into" }))
		map("n", "<leader>do", dap.step_over, vim.tbl_extend("force", opts, { desc = "DAP Step Over" }))
		map("n", "<leader>dO", dap.step_out, vim.tbl_extend("force", opts, { desc = "DAP Step Out" }))
		map("n", "<leader>dn", dap.goto_, vim.tbl_extend("force", opts, { desc = "DAP Next Breakpoint" }))
		map("n", "<leader>dr", dap.repl.open, vim.tbl_extend("force", opts, { desc = "DAP REPL" }))
		map("n", "<leader>du", dapui.toggle, vim.tbl_extend("force", opts, { desc = "DAP UI" }))
	end,
}
