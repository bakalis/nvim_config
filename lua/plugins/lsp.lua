return {
	"neovim/nvim-lspconfig",
	dependencies = {
		{ "williamboman/mason.nvim", config = true },
		"williamboman/mason-lspconfig.nvim",
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
		-- HELPER: get python interpreter for venv
		---------------------------------------------------------------------------
		local function get_python_path()
			-- Try $VIRTUAL_ENV
			local venv = vim.fn.getenv("VIRTUAL_ENV")
			if venv ~= vim.NIL and vim.fn.isdirectory(venv) == 1 then
				return venv .. "/bin/python"
			end
			-- Try .venv in project root
			local local_venv = vim.fn.getcwd() .. "/.venv/bin/python"
			if vim.fn.filereadable(local_venv) == 1 then
				return local_venv
			end
			-- fallback system Python
			return "/usr/bin/python3"
		end

		---------------------------------------------------------------------------
		-- HELPER: auto-install pylsp in venv if missing
		---------------------------------------------------------------------------
		local function ensure_pylsp_installed(python)
			local handle = io.popen(python .. " -m pip show python-lsp-server")
			local result = handle:read("*a")
			handle:close()
			if result == "" then
				vim.notify("Installing python-lsp-server in venv: " .. python, vim.log.levels.INFO)
				os.execute(python .. " -m pip install 'python-lsp-server[all]'")
			end
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

			pylsp = (function()
				local python_path = get_python_path()
				ensure_pylsp_installed(python_path) -- auto-install if missing
				return {
					cmd = { python_path, "-m", "pylsp" },
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
				}
			end)(),

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
		-- MASON SETUP
		---------------------------------------------------------------------------
		require("mason").setup()

		require("mason-tool-installer").setup({
			ensure_installed = {
				"rust-analyzer",
				"lua-language-server",
				"python-lsp-server",
				"stylua",
			},
		})

		require("mason-lspconfig").setup()

		---------------------------------------------------------------------------
		-- ENABLE ALL MASON-INSTALLED LSP SERVERS
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
