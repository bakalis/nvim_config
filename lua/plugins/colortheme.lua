return {
	"yorumicolors/yorumi.nvim",
	lazy = false,
	priority = 1000,
	config = function()
		-- Groups whose background is dropped for a transparent terminal look
		local transparent_groups = {
			"Normal",
			"NormalNC",
			"NormalFloat",
			"SignColumn",
			"EndOfBuffer",
			"MsgArea",
			"FoldColumn",
			"LineNr",
			"CursorLineNr",
			"NeoTreeNormal",
			"NeoTreeNormalNC",
			"NeoTreeEndOfBuffer",
		}

		local bg_transparent = true

		local function apply_transparency()
			if not bg_transparent then
				return
			end
			for _, group in ipairs(transparent_groups) do
				local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
				hl.bg = nil
				hl.ctermbg = nil
				vim.api.nvim_set_hl(0, group, hl)
			end
		end

		-- Re-applied on every colorscheme load, plugins reset highlights when they load
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("yorumi-transparency", { clear = true }),
			pattern = "yorumi",
			callback = apply_transparency,
		})

		vim.cmd.colorscheme("yorumi")

		-- Toggle background transparency
		vim.keymap.set("n", "<leader>bg", function()
			bg_transparent = not bg_transparent
			vim.cmd.colorscheme("yorumi")
		end, { noremap = true, silent = true, desc = "Toggle transparent background" })
	end,
}
