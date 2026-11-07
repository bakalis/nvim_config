return { -- Autocompletion
	"saghen/blink.cmp",
	version = "1.*",
	dependencies = {
		"rafamadriz/friendly-snippets",
		"giuxtaposition/blink-cmp-copilot",
	},
	---@module 'blink.cmp'
	opts = {
		-- See `:help ins-completion` for the keys' fallbacks
		keymap = {
			preset = "none",
			["<C-n>"] = { "select_next", "fallback" },
			["<C-p>"] = { "select_prev", "fallback" },
			["<C-b>"] = { "scroll_documentation_up", "fallback" },
			["<C-f>"] = { "scroll_documentation_down", "fallback" },
			["<CR>"] = { "accept", "fallback" },
			["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
			["<C-l>"] = { "snippet_forward", "fallback" },
			["<C-h>"] = { "snippet_backward", "fallback" },
			["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
			["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
		},
		completion = {
			list = { selection = { preselect = true, auto_insert = true } },
			menu = {
				max_height = 10,
				draw = { columns = { { "kind_icon" }, { "label", "label_description", gap = 1 }, { "source_name" } } },
			},
			documentation = { auto_show = true },
		},
		snippets = { preset = "default" },
		sources = {
			default = { "lsp", "path", "snippets", "buffer", "copilot" },
			-- table and column names from the connection selected in the database UI
			per_filetype = {
				sql = { "snippets", "dadbod", "buffer" },
				mysql = { "snippets", "dadbod", "buffer" },
				plsql = { "snippets", "dadbod", "buffer" },
			},
			providers = {
				dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" },
				copilot = {
					name = "copilot",
					module = "blink-cmp-copilot",
					score_offset = 100,
					async = true,
				},
			},
		},
		signature = { enabled = true },
	},
	opts_extend = { "sources.default" },
}
