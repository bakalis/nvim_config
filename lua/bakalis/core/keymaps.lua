vim.g.mapleader = " "

local keymap = vim.keymap -- for conciseness

keymap.set("n", "<leader>t", function()
	vim.cmd("split | terminal")
end, { noremap = true, silent = true, desc = "Open terminal in split" })

keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode with jk" })

keymap.set("n", "<leader>nh", ":nohl<CR>", { desc = "Clear search highlights" })

-- increment/decrement numbers
keymap.set("n", "<leader>+", "<C-a>", { desc = "Increment number" }) -- increment
keymap.set("n", "<leader>-", "<C-x>", { desc = "Decrement number" }) -- decrement

-- window management
keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split window vertically" }) -- split window vertically
keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split window horizontally" }) -- split window horizontally
keymap.set("n", "<leader>se", "<C-w>=", { desc = "Make splits equal size" }) -- make split windows equal width & height
keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close current split" }) -- close current split window

keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "Open new tab" }) -- open new tab
keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close current tab" }) -- close current tab
keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Go to next tab" }) --  go to next tab
keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Go to previous tab" }) --  go to previous tab
keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buffer in new tab" }) --  move current buffer to new tab

vim.cmd("set whichwrap+=<,>,h,l")
local opts = { noremap = true, silent = true }

keymap.set("n", "<C-h>", "<C-w>h", { noremap = true, silent = true })

-- UP arrow
keymap.set({ "n", "v" }, "<Up>", function()
	if vim.fn.line(".") == 1 then
		vim.cmd("normal! 0")
	else
		vim.cmd("normal! k")
	end
end, opts)

keymap.set("i", "<Up>", function()
	if vim.fn.line(".") == 1 then
		return "<Esc>0i"
	else
		return "<Up>"
	end
end, { expr = true })

-- DOWN arrow
keymap.set({ "n", "v" }, "<Down>", function()
	if vim.fn.line(".") == vim.fn.line("$") then
		vim.cmd("normal! $")
	else
		vim.cmd("normal! j")
	end
end, opts)

keymap.set("i", "<Down>", function()
	if vim.fn.line(".") == vim.fn.line("$") then
		return "<Esc>$a"
	else
		return "<Down>"
	end
end, { expr = true })

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
	pattern = "*",
	callback = function()
		if vim.bo.modified and vim.fn.empty(vim.bo.buftype) == 1 then
			vim.cmd("silent! write")
		end
	end,
})

-- Smart 'k'
keymap.set({ "n", "v" }, "k", function()
	if vim.v.count == 0 and vim.fn.line(".") == 1 then
		vim.cmd("normal! 0")
	else
		vim.cmd("normal! " .. vim.v.count1 .. "k")
	end
end, opts)

keymap.set("i", "k", function()
	if vim.fn.line(".") == 1 then
		return "<Esc>0i"
	else
		return "k"
	end
end, { expr = true })

-- Smart 'j'
keymap.set({ "n", "v" }, "j", function()
	if vim.v.count == 0 and vim.fn.line(".") == vim.fn.line("$") then
		vim.cmd("normal! $")
	else
		vim.cmd("normal! " .. vim.v.count1 .. "j")
	end
end, opts)

keymap.set("i", "j", function()
	if vim.fn.line(".") == vim.fn.line("$") then
		return "<Esc>$a"
	else
		return "j"
	end
end, { expr = true })
