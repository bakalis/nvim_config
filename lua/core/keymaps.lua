-- Set leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disable the spacebar key's default behavior in Normal and Visual modes
vim.keymap.set({ "n", "v" }, "<Space>", "<Nop>", { silent = true })

local function get_buf_list()
	local bufs = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_option(buf, "buflisted") then
			table.insert(bufs, buf)
		end
	end
	return bufs
end

local function close_buffer(buf, force)
	local ok, err = pcall(vim.api.nvim_buf_delete, buf, { force = force })
	if not ok then
		vim.notify("Failed to close buffer: " .. err, vim.log.levels.WARN)
	end
end

vim.keymap.set("n", "<leader>bd", function()
	local current = vim.api.nvim_get_current_buf()
	local buffers = vim.fn.getbufinfo({ buflisted = 1 })

	-- If this is the only listed buffer, just delete it
	if #buffers <= 1 then
		vim.api.nvim_buf_delete(current, { force = false })
		return
	end

	-- Otherwise, switch to most recently used buffer
	for _, buf in ipairs(buffers) do
		if buf.bufnr ~= current then
			vim.api.nvim_set_current_buf(buf.bufnr)
			break
		end
	end

	vim.api.nvim_buf_delete(current, { force = false })
end, { desc = "Delete buffer and go to last buffer" })

-- Close all other buffers
vim.keymap.set("n", "<leader>bo", function()
	local cur = vim.api.nvim_get_current_buf()
	for _, buf in ipairs(get_buf_list()) do
		if buf ~= cur then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end
end, { desc = "Close all other buffers" })

-- Close all buffers
vim.keymap.set("n", "<leader>ba", function()
	for _, buf in ipairs(get_buf_list()) do
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end, { desc = "Close all buffers" })
-- For conciseness
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
vim.keymap.set("n", "<leader>v", "<C-w>v", opts) -- split window vertically
vim.keymap.set("n", "<leader>h", "<C-w>s", opts) -- split window horizontally
vim.keymap.set("n", "<leader>se", "<C-w>=", opts) -- make split windows equal width & height
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
