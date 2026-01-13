-- Set leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disable the spacebar key's default behavior in Normal and Visual modes

vim.keymap.set({ "n", "v" }, "<Space>", "<Nop>", { silent = true })
-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

local function listed_buffers()
	local bufs = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_get_option_value("buflisted", { buf = buf }) then
			table.insert(bufs, buf)
		end
	end
	return bufs
end

local function is_modified(buf)
	return vim.api.nvim_get_option_value("modified", { buf = buf })
end

local function confirm_force(msg)
	return vim.fn.confirm(msg, "&Yes\n&No", 2) == 1
end

local function goto_alternate_buffer(current)
	for _, buf in ipairs(listed_buffers()) do
		if buf ~= current then
			vim.api.nvim_set_current_buf(buf)
			return true
		end
	end
	return false
end

local function delete_buffer(buf)
	local modified = is_modified(buf)

	if modified then
		if not confirm_force("Buffer has unsaved changes. Force close?") then
			return
		end
	end

	-- Switch first if possible
	goto_alternate_buffer(buf)

	vim.api.nvim_buf_delete(buf, { force = modified })
end

-- ---------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------

-- Delete current buffer (IntelliJ-style)
vim.keymap.set("n", "<leader>bd", function()
	delete_buffer(vim.api.nvim_get_current_buf())
end, { desc = "Delete buffer (confirm if modified)" })

-- Close all other buffers (confirm per modified buffer)
vim.keymap.set("n", "<leader>bo", function()
	local cur = vim.api.nvim_get_current_buf()
	for _, buf in ipairs(listed_buffers()) do
		if buf ~= cur then
			delete_buffer(buf)
		end
	end
end, { desc = "Close other buffers (confirm modified)" })

-- Close all buffers (confirm per modified buffer)
vim.keymap.set("n", "<leader>ba", function()
	for _, buf in ipairs(listed_buffers()) do
		delete_buffer(buf)
	end
end, { desc = "Close all buffers (confirm modified)" })

local opts = { noremap = true, silent = true }

-- save file
vim.keymap.set("n", "<C-s>", "<cmd> w <CR>", opts)

-- save file without auto-formatting
vim.keymap.set("n", "<leader>sn", "<cmd>noautocmd w <CR>", opts)

-- quit file
vim.keymap.set("n", "<C-q>", "<cmd> q <CR>", opts)

-- delete single character without copying into register
vim.keymap.set("n", "x", '"_x', opts)

-- Vertical scroll and center
vim.keymap.set("n", "<C-d>", "<C-d>zz", opts)
vim.keymap.set("n", "<C-u>", "<C-u>zz", opts)

-- Find and center
vim.keymap.set("n", "n", "nzzzv", opts)
vim.keymap.set("n", "N", "Nzzzv", opts)

-- Resize with arrows
vim.keymap.set("n", "<Up>", ":resize -2<CR>", opts)
vim.keymap.set("n", "<Down>", ":resize +2<CR>", opts)
vim.keymap.set("n", "<Left>", ":vertical resize -2<CR>", opts)
vim.keymap.set("n", "<Right>", ":vertical resize +2<CR>", opts)

-- Buffers
vim.keymap.set("n", "<Tab>", ":bnext<CR>", opts)
vim.keymap.set("n", "<S-Tab>", ":bprevious<CR>", opts)
vim.keymap.set("n", "<leader>x", ":bdelete!<CR>", opts) -- close buffer
vim.keymap.set("n", "<leader>b", "<cmd> enew <CR>", opts) -- new buffer

-- Window management
vim.keymap.set("n", "<leader>xv", "<C-w>v", opts) -- split window vertically
vim.keymap.set("n", "<leader>xh", "<C-w>s", opts) -- split window horizontally
vim.keymap.set("n", "<leader>xe", "<C-w>=", opts) -- make split windows equal width & height
vim.keymap.set("n", "<leader>xs", ":close<CR>", opts) -- close current split window

-- Navigate between splits
vim.keymap.set("n", "<C-k>", ":wincmd k<CR>", opts)
vim.keymap.set("n", "<C-j>", ":wincmd j<CR>", opts)
vim.keymap.set("n", "<C-h>", ":wincmd h<CR>", opts)
vim.keymap.set("n", "<C-l>", ":wincmd l<CR>", opts)

-- Tabs
vim.keymap.set("n", "<leader>to", ":tabnew<CR>", opts) -- open new tab
vim.keymap.set("n", "<leader>tx", ":tabclose<CR>", opts) -- close current tab
vim.keymap.set("n", "<leader>tn", ":tabn<CR>", opts) --  go to next tab
vim.keymap.set("n", "<leader>tp", ":tabp<CR>", opts) --  go to previous tab

-- Toggle line wrapping
vim.keymap.set("n", "<leader>lw", "<cmd>set wrap!<CR>", opts)

-- Stay in indent mode
vim.keymap.set("v", "<", "<gv", opts)
vim.keymap.set("v", ">", ">gv", opts)

-- Keep last yanked when pasting
vim.keymap.set("v", "p", '"_dP', opts)

-- Diagnostic keymaps
vim.keymap.set("n", "[d", function()
	vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Go to previous diagnostic message" })

vim.keymap.set("n", "]d", function()
	vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Go to next diagnostic message" })

vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, { desc = "Open floating diagnostic message" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostics list" })

-- Smart 'k'
vim.keymap.set({ "n", "v" }, "k", function()
	if vim.v.count == 0 and vim.fn.line(".") == 1 then
		vim.cmd("normal! 0")
	else
		vim.cmd("normal! " .. vim.v.count1 .. "k")
	end
end, opts)

vim.keymap.set("n", "k", function()
	if vim.fn.line(".") == 1 then
		return "<Esc>0"
	else
		return "k"
	end
end, { expr = true })

-- Smart 'j'
vim.keymap.set({ "n", "v" }, "j", function()
	if vim.v.count == 0 and vim.fn.line(".") == vim.fn.line("$") then
		vim.cmd("normal! $")
	else
		vim.cmd("normal! " .. vim.v.count1 .. "j")
	end
end, opts)

vim.keymap.set("n", "j", function()
	if vim.fn.line(".") == vim.fn.line("$") then
		return "<Esc>$"
	else
		return "j"
	end
end, { expr = true })

vim.keymap.set("n", "<leader>gd", function()
	local gs = require("gitsigns")
	gs.diffthis() -- opens a diff of current buffer vs HEAD in a split
end, { noremap = true, silent = true, desc = "Git diff current buffer" })

vim.keymap.set("n", "K", function()
	local word = vim.fn.expand("<cword>")

	-- Check if a help page exists
	local help_tags = vim.fn.getcompletion(word, "help")

	if #help_tags > 0 then
		-- find Neo-tree width if exists
		local neo_width = 0
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			local b = vim.api.nvim_win_get_buf(w)
			if vim.bo[b].filetype == "neo-tree" then
				neo_width = vim.api.nvim_win_get_width(w)
				break
			end
		end

		-- open help in horizontal split at bottom
		vim.cmd("belowright help " .. help_tags[1])

		-- adjust width so it doesn't cover Neo-tree
		pcall(vim.api.nvim_win_set_width, 0, vim.o.columns - neo_width)
		vim.cmd("resize 15") -- optional: fixed height
	else
		vim.notify("No help page exists for: " .. word, vim.log.levels.INFO, { title = "Help" })
	end
end, { desc = "Open help for word under cursor in horizontal split (safe)" })

vim.keymap.set("n", "<leader>j", function()
	local count = vim.v.count1
	vim.cmd(string.format("m .+%d", count))
	vim.cmd("normal! ==")
end, { desc = "Move line down" })

vim.keymap.set("n", "<leader>k", function()
	local count = vim.v.count1
	vim.cmd(string.format("m .-%d", count + 1))
	vim.cmd("normal! ==")
end, { desc = "Move line up" })

vim.keymap.set("v", "<leader>j", ":m'>+<CR>gv=gv", { desc = "Move down" })
vim.keymap.set("v", "<leader>k", ":m-2<CR>gv=gv", { desc = "Move up" })

vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
