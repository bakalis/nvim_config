-- Custom code snippets for different purposes

-- Prevent LSP from overwriting treesitter color settings
-- https://github.com/NvChad/NvChad/issues/1907
vim.hl.priorities.semantic_tokens = 95 -- Or any number lower than 100, treesitter's priority level

-- Appearance of diagnostics
vim.diagnostic.config({
	virtual_text = {
		prefix = "●",
		-- Add a custom format function to show error codes
		format = function(diagnostic)
			local code = diagnostic.code and string.format("[%s]", diagnostic.code) or ""
			return string.format("%s %s", code, diagnostic.message)
		end,
	},
	underline = false,
	update_in_insert = true,
	float = {
		source = true, -- Or "if_many"
	},
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = " ",
			[vim.diagnostic.severity.WARN] = " ",
			[vim.diagnostic.severity.INFO] = " ",
			[vim.diagnostic.severity.HINT] = "󰌵 ",
		},
	},
	-- Make diagnostic background transparent
	on_ready = function()
		vim.cmd("highlight DiagnosticVirtualText guibg=NONE")
	end,
})

-- Highlight on yank
local highlight_group = vim.api.nvim_create_augroup("YankHighlight", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
	callback = function()
		vim.hl.on_yank()
	end,
	group = highlight_group,
	pattern = "*",
})

-- Open help in a horizontal split at bottom and adjust width for Neo-tree
vim.api.nvim_create_autocmd("FileType", {
	pattern = "help",
	callback = function(event)
		local buf = event.buf
		local opts = { buffer = buf, silent = true }

		-- keymaps to quit help
		vim.keymap.set("n", "q", "<cmd>close<cr>", opts)
		vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", opts)

		-- no numbers in help
		vim.wo.number = false
		vim.wo.relativenumber = false
	end,
})

vim.keymap.set("n", "K", function()
	local word = vim.fn.expand("<cword>")

	-- find Neo-tree width if exists
	local neo_width = 0
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		local b = vim.api.nvim_win_get_buf(w)
		if vim.bo[b].filetype == "neo-tree" then
			neo_width = vim.api.nvim_win_get_width(w)
			break
		end
	end

	-- open help in horizontal split directly
	vim.cmd("belowright help " .. word)

	-- adjust width so it doesn't cover Neo-tree
	local ok, _ = pcall(vim.api.nvim_win_set_width, 0, vim.o.columns - neo_width)
	vim.cmd("resize 15") -- set height
end, { desc = "Open help for word under cursor in horizontal split" })
