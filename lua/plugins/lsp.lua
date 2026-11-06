return {
	"neovim/nvim-lspconfig",
	dependencies = {
		{ "mason-org/mason.nvim", config = true },
		"mason-org/mason-lspconfig.nvim",
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		"saghen/blink.cmp",
		{
			"folke/lazydev.nvim",
			ft = "lua",
			opts = { library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } } },
		},

		{
			"j-hui/fidget.nvim",
			opts = {
				notification = { window = { winblend = 0 } },
			},
		},
	},

	config = function()
		---------------------------------------------------------------------------
		-- LSP ATTACH KEYMAPS
		---------------------------------------------------------------------------
		vim.api.nvim_create_autocmd("LspAttach", {
			group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
			callback = function(event)
				local map = function(keys, func, desc, mode)
					vim.keymap.set(mode or "n", keys, func, {
						buffer = event.buf,
						desc = "LSP: " .. desc,
					})
				end

				local tb = require("telescope.builtin")
				map("gd", tb.lsp_definitions, "Goto Definition")
				map("gr", tb.lsp_references, "Find References")
				map("gI", tb.lsp_implementations, "Goto Implementation")
				map("<leader>D", tb.lsp_type_definitions, "Type Definition")
				map("<leader>rn", vim.lsp.buf.rename, "Rename")
				map("<leader>ca", vim.lsp.buf.code_action, "Code Action", { "n", "x" })
				map("gD", vim.lsp.buf.declaration, "Goto Declaration")

				local client = vim.lsp.get_client_by_id(event.data.client_id)
				if client and client:supports_method("textDocument/inlayHint") then
					vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
					map("<leader>th", function()
						vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }), { bufnr = event.buf })
					end, "Toggle Inlay Hints")
				end
			end,
		})

		---------------------------------------------------------------------------
		-- CAPABILITIES
		---------------------------------------------------------------------------
		local capabilities = vim.lsp.protocol.make_client_capabilities()
		capabilities = vim.tbl_deep_extend("force", capabilities, require("blink.cmp").get_lsp_capabilities())

		---------------------------------------------------------------------------
		-- HELPER: python interpreter for the current project (venv aware)
		---------------------------------------------------------------------------
		local function get_python_path(root)
			local venv = vim.env.VIRTUAL_ENV
			if venv and vim.fn.isdirectory(venv) == 1 then
				return venv .. "/bin/python"
			end
			local local_venv = (root or vim.fn.getcwd()) .. "/.venv/bin/python"
			if vim.fn.executable(local_venv) == 1 then
				return local_venv
			end
			return nil
		end

		---------------------------------------------------------------------------
		-- SERVER OVERRIDES
		---------------------------------------------------------------------------
		local servers = {
			rust_analyzer = {
				settings = {
					["rust-analyzer"] = {
						checkOnSave = true,
						check = { command = "clippy" },
					},
				},
			},

			pylsp = {
				-- Use the project venv's pylsp when it has one, otherwise mason's pylsp
				before_init = function(_, config)
					local python = get_python_path(config.root_dir)
					if python then
						vim.fn.system({ python, "-c", "import pylsp" })
						if vim.v.shell_error == 0 then
							config.cmd = { python, "-m", "pylsp" }
						end
					end
				end,
				settings = {
					pylsp = {
						plugins = {
							pyflakes = { enabled = false },
							pycodestyle = { enabled = false },
							autopep8 = { enabled = false },
							yapf = { enabled = false },
							mccabe = { enabled = false },
						},
					},
				},
			},

			lua_ls = {
				settings = {
					Lua = {
						runtime = { version = "LuaJIT" },
						diagnostics = { globals = { "vim" } },
						workspace = { checkThirdParty = false },
						format = { enable = false },
					},
				},
			},
		}

		---------------------------------------------------------------------------
		-- MASON SETUP
		---------------------------------------------------------------------------
		require("mason").setup()

		require("mason-tool-installer").setup({
			ensure_installed = {
				"rust-analyzer",
				"lua-language-server",
				"python-lsp-server",
				"stylua",
				"tree-sitter-cli",
				"prettier",
				"eslint_d",
				"shfmt",
				"checkmake",
				"ruff",
			},
		})

		-- Configure overrides, then let mason-lspconfig enable every installed server
		for server, cfg in pairs(servers) do
			cfg.capabilities = vim.tbl_deep_extend("force", {}, capabilities, cfg.capabilities or {})
			vim.lsp.config(server, cfg)
		end
		vim.lsp.config("*", { capabilities = capabilities })

		require("mason-lspconfig").setup({ automatic_enable = true })
	end,
}
