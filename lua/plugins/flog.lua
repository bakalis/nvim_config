-- Interactive git graph in a buffer, builds on vim-fugitive. Opens in its own tab, gq closes it
return {
	"rbong/vim-flog",
	dependencies = { "tpope/vim-fugitive" },
	cmd = { "Flog", "Flogsplit", "Floggit" },
	keys = {
		{ "<leader>gg", "<cmd>Flog<cr>", desc = "Git graph (all branches)" },
		{ "<leader>gG", "<cmd>Flog -path=%<cr>", desc = "Git graph of the current file" },
	},
	init = function()
		-- Same key as the changes view (<leader>gv): open the commit under the cursor in codediff
		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("flog-codediff", { clear = true }),
			pattern = "floggraph",
			callback = function(event)
				vim.keymap.set("n", "<leader>gv", function()
					local commit = vim.fn["flog#floggraph#commit#GetAtLine"](".")
					local hash = commit and commit.hash
					if not hash or hash == "" then
						return
					end
					local parent = vim.trim(vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", hash .. "^" }))
					if vim.v.shell_error ~= 0 then
						parent = "4b825dc642cb6eb9a060e54bf8d69288fbee4904" -- empty tree, for the first commit
					end
					vim.cmd("CodeDiff " .. parent .. " " .. hash)
				end, { buffer = event.buf, silent = true, desc = "Diff: commit under cursor in codediff" })
			end,
		})

		vim.g.flog_enable_dynamic_commit_hl = 1
		-- not -all: that would also list refs/stash entries as commits
		vim.g.flog_default_opts = { rev = { "--branches", "--remotes", "--tags", "HEAD" }, max_count = 2000, date = "short" }
	end,
}
