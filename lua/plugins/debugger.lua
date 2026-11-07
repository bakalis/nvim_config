return {
	"mfussenegger/nvim-dap",
	dependencies = {
		"mason-org/mason.nvim",
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
						{ id = "repl", size = 1.0 },
					},
					size = 10,
					position = "bottom",
				},
			},
		})

		-- dap-ui makes its single "DAP Console" buffer the terminal of every session, so a
		-- second running app fails to start (jobstart requires an unmodified buffer).
		-- Every session gets its own terminal window at the bottom instead.
		dap.defaults.fallback.terminal_win_cmd = function()
			local current = vim.api.nvim_get_current_win()
			vim.cmd("botright 12new")
			local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
			vim.api.nvim_set_current_win(current)
			return buf, win
		end

		require("nvim-dap-virtual-text").setup({ commented = true })

		-- nvim-dap reuses the terminal buffer of a finished session, and on Neovim 0.12 that
		-- fails ("jobstart(...,{term=true}) requires unmodified buffer") once the previous
		-- app was stopped. Wipe finished debug terminals before a new session starts.
		dap.listeners.on_config["wipe-finished-terminals"] = function(config)
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" and vim.b[buf]["dap-type"] then
					local job = vim.b[buf].terminal_job_id
					if not job or vim.fn.jobwait({ job }, 0)[1] ~= -1 then
						pcall(vim.api.nvim_buf_delete, buf, { force = true })
					end
				end
			end
			return config
		end

		-- Stopping a session must also stop the app: it runs in a terminal job that the
		-- debug adapter can't kill, so it kept running (and holding its port) after "stop"
		local function stop_terminal_job(session)
			local buf = session and session.term_buf
			if buf and vim.api.nvim_buf_is_valid(buf) then
				local job = vim.b[buf].terminal_job_id
				if job then
					pcall(vim.fn.jobstop, job)
				end
			end
		end
		dap.listeners.after.event_terminated["stop-terminal-job"] = stop_terminal_job
		dap.listeners.after.event_exited["stop-terminal-job"] = stop_terminal_job
		dap.listeners.after.disconnect["stop-terminal-job"] = stop_terminal_job

		-- Auto open/close UI
		dap.listeners.after.event_initialized["dapui"] = function(session)
			-- plain runs (<leader>Jr, services panel) don't need the debug layout
			if session.config.noDebug then
				return
			end
			dapui.open()
		end
		dap.listeners.before.event_terminated["dapui"] = function()
			dapui.close()
		end
		dap.listeners.before.event_exited["dapui"] = function()
			dapui.close()
		end

		-- Breakpoint signs, independent of the colorscheme (re-applied when it changes)
		local function define_dap_highlights()
			vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#f92672" })
			vim.api.nvim_set_hl(0, "DapBreakpointCondition", { fg = "#e6db74" })
			vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#ae81ff" })
			vim.api.nvim_set_hl(0, "DapStopped", { fg = "#66d9ef", bold = true })
			vim.api.nvim_set_hl(0, "DapStoppedLine", { bg = "#2d344a" })
		end
		define_dap_highlights()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("dap-highlights", { clear = true }),
			callback = define_dap_highlights,
		})

		vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint" })
		vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DapBreakpointCondition" })
		vim.fn.sign_define("DapLogPoint", { text = "◆", texthl = "DapLogPoint" })
		vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DapStopped", linehl = "DapStoppedLine" })

		-- Keymaps
		local map = vim.keymap.set
		local opts = { silent = true }
		map("n", "<leader>dc", dap.continue, vim.tbl_extend("force", opts, { desc = "DAP Continue" }))
		map("n", "<leader>db", dap.toggle_breakpoint, vim.tbl_extend("force", opts, { desc = "DAP Breakpoint" }))
		map("n", "<leader>di", dap.step_into, vim.tbl_extend("force", opts, { desc = "DAP Step Into" }))
		map("n", "<leader>do", dap.step_over, vim.tbl_extend("force", opts, { desc = "DAP Step Over" }))
		map("n", "<leader>dO", dap.step_out, vim.tbl_extend("force", opts, { desc = "DAP Step Out" }))
		map("n", "<leader>dn", dap.goto_, vim.tbl_extend("force", opts, { desc = "DAP Next Breakpoint" }))
		map("n", "<leader>dB", function()
			dap.set_breakpoint(vim.fn.input("Condition: "))
		end, vim.tbl_extend("force", opts, { desc = "DAP Conditional Breakpoint" }))
		map("n", "<leader>dL", function()
			dap.set_breakpoint(nil, nil, vim.fn.input("Log message: "))
		end, vim.tbl_extend("force", opts, { desc = "DAP Logpoint" }))
		map("n", "<leader>dE", function()
			dap.set_exception_breakpoints()
		end, vim.tbl_extend("force", opts, { desc = "DAP Exception Breakpoints" }))
		map("n", "<leader>dC", dap.run_to_cursor, vim.tbl_extend("force", opts, { desc = "DAP Run to Cursor" }))
		map("n", "<leader>dR", dap.restart, vim.tbl_extend("force", opts, { desc = "DAP Restart" }))
		map("n", "<leader>dt", dap.terminate, vim.tbl_extend("force", opts, { desc = "DAP Terminate" }))
		map("n", "<leader>dr", dap.repl.open, vim.tbl_extend("force", opts, { desc = "DAP REPL" }))
		map("n", "<leader>du", dapui.toggle, vim.tbl_extend("force", opts, { desc = "DAP UI" }))
		vim.keymap.set("n", "<space>?", function()
			require("dapui").eval(nil, { enter = true })
		end)
	end,
}
