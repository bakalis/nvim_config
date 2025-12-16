return {
	"neovim/nvim-lspconfig",
	dependencies = {
		{ "mason-org/mason.nvim", config = true },
		"mason-org/mason-lspconfig.nvim",
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		"hrsh7th/cmp-nvim-lsp",

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
			end,
		})

		---------------------------------------------------------------------------
		-- CAPABILITIES
		---------------------------------------------------------------------------
		local capabilities = vim.lsp.protocol.make_client_capabilities()
		capabilities = vim.tbl_deep_extend("force", capabilities, require("cmp_nvim_lsp").default_capabilities())

		---------------------------------------------------------------------------
		-- SERVER OVERRIDES (ONLY WHAT YOU WANT TO CUSTOMIZE)
		---------------------------------------------------------------------------
		local servers = {
			rust_analyzer = {
				settings = {
					["rust-analyzer"] = {
						cargo = { allFeatures = true },
						checkOnSave = { command = "clippy" },
					},
				},
			},

			pylsp = {
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
						workspace = {
							checkThirdParty = false,
							library = vim.api.nvim_get_runtime_file("", true),
						},
						format = { enable = false },
					},
				},
			},
		}

		---------------------------------------------------------------------------
		-- MASON
		---------------------------------------------------------------------------
		require("mason").setup()

		-- Install tools (LSPs + formatters)
		require("mason-tool-installer").setup({
			ensure_installed = {
				-- LSPs
				"rust-analyzer",
				"lua-language-server",
				"python-lsp-server",

				-- formatters / tools (NOT LSPs)
				"stylua",
			},
		})

		require("mason-lspconfig").setup()

		---------------------------------------------------------------------------
		-- ENABLE ALL MASON-INSTALLED LSP SERVERS (NEW API)
		---------------------------------------------------------------------------
		local installed_lsps = require("mason-lspconfig").get_installed_servers()

		for _, server in ipairs(installed_lsps) do
			local cfg = servers[server] or {}
			cfg.capabilities = vim.tbl_deep_extend("force", {}, capabilities, cfg.capabilities or {})

			vim.lsp.config(server, cfg)
			vim.lsp.enable(server)
		end
	end,
}
