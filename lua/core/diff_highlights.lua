-- IntelliJ style diff colors, whatever the colorscheme: a tinted background for changed lines and a
-- stronger one for the characters that changed inside them. Tints are blended into the current
-- Normal background, so they follow transparency/theme changes.
--   nvim -d / :Gvdiffsplit / git difftool nvimdiff use DiffAdd, DiffChange, DiffDelete, DiffText
--   codediff.nvim derives its line and character colors from DiffAdd and DiffDelete
local function blend(color, background, alpha)
	local function channel(shift)
		local c = bit.band(bit.rshift(color, shift), 0xff)
		local b = bit.band(bit.rshift(background, shift), 0xff)
		return math.floor(b + (c - b) * alpha + 0.5)
	end
	return bit.lshift(channel(16), 16) + bit.lshift(channel(8), 8) + channel(0)
end

local function apply()
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local dark = vim.o.background ~= "light"
	local background = normal.bg or (dark and 0x1a1b26 or 0xffffff)
	local line, text = dark and 0.17 or 0.14, dark and 0.40 or 0.30

	local green, red, blue = 0x4caf50, 0xe5534b, 0x4c8bf5
	local set = function(group, color, alpha, extra)
		vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", { bg = blend(color, background, alpha) }, extra or {}))
	end
	set("DiffAdd", green, line)
	set("DiffDelete", red, line)
	set("DiffChange", blue, line)
	set("DiffText", blue, text, { bold = true })

	-- codediff computes its colors from the groups above when it sets up
	if package.loaded["codediff.ui.highlights"] then
		pcall(function()
			require("codediff.ui.highlights").setup()
		end)
	end
end

local group = vim.api.nvim_create_augroup("diff-highlights", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = apply })
-- themes that tweak Normal after loading (transparency, custom backgrounds) are settled by now
vim.api.nvim_create_autocmd("VimEnter", { group = group, callback = vim.schedule_wrap(apply) })
apply()
