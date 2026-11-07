-- Entry point for `git difftool` (tool "codediff"). Git starts nvim as
--   nvim "$REMOTE" "$LOCAL" -c "lua require('core.difftool').run()"
-- where the two paths are files or, with --dir-diff, directories. They come in as arguments because
-- git only sets LOCAL/REMOTE as shell variables, and this also avoids quoting problems.
local M = {}

function M.run()
	local right, left = vim.fn.argv(0), vim.fn.argv(1)
	if right == "" or left == "" then
		vim.notify("difftool: expected the REMOTE and LOCAL paths as arguments", vim.log.levels.ERROR)
		return
	end
	local is_dir = vim.fn.isdirectory(right) == 1
	-- git passes directories with a trailing slash, codediff rejects those
	left, right = left:gsub("/+$", ""), right:gsub("/+$", "")
	vim.cmd(string.format(
		"CodeDiff --exit-on-close %s %s %s",
		is_dir and "dir" or "file",
		vim.fn.fnameescape(left),
		vim.fn.fnameescape(right)
	))
end

return M
