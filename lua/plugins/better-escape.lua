-- jj and jk leave insert mode (the plugin's default mappings also cover command-line, visual, select and terminal
-- mode). The second key has to come within `timeout` ms of the first, so a slower jj still types two j's.
return {
	"max397574/better-escape.nvim",
	event = "InsertEnter",
	opts = {
		timeout = 200, -- own timeout, separate from the global `timeoutlen` (300)
	},
	config = function(_, opts)
		require("better_escape").setup(opts)

		-- The plugin maps j and k in visual and select mode (for jk), replacing the "smart" j and k of
		-- core/keymaps.lua that jump to the end of the last line and the start of the first line. These keep the
		-- plugin's own mapping for the escape sequence and add the jump on top, as the plugin maps are expressions.
		for _, mode in ipairs({ "v", "s" }) do
			local plugin_j = vim.fn.maparg("j", mode, false, true).callback
			local plugin_k = vim.fn.maparg("k", mode, false, true).callback
			if plugin_j and plugin_k then
				vim.keymap.set(mode, "j", function()
					local keys = plugin_j()
					if keys == "j" and vim.v.count == 0 and vim.fn.line(".") == vim.fn.line("$") then
						return "$"
					end
					return keys
				end, { expr = true, silent = true })
				vim.keymap.set(mode, "k", function()
					local keys = plugin_k()
					if keys == "k" and vim.v.count == 0 and vim.fn.line(".") == 1 then
						return "0"
					end
					return keys
				end, { expr = true, silent = true })
			end
		end
	end,
}
