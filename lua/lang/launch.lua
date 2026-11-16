-- Run configurations, IntelliJ style, shared by the languages in this folder (rust.lua, python.lua).
-- Saved ones live in <project>/.vscode/launch.json, the file VS Code uses, so they can be shared with
-- a team. Each language adds the configurations it discovers by itself (binaries, the current file, ...).
local platform = require("core.platform")

local M = {}

function M.path(root)
	return platform.join(root, ".vscode", "launch.json")
end

--- The configurations of <root>/.vscode/launch.json whose "type" is one of `types` (a set)
function M.saved(root, types)
	local ok, configs = pcall(require("dap.ext.vscode").getconfigs, M.path(root))
	return vim.tbl_filter(function(config)
		return types[config.type] == true
	end, ok and configs or {})
end

--- Saved configurations first, then the discovered ones that no saved one replaces (same name)
function M.merge(saved, discovered)
	local configs, covered = vim.deepcopy(saved), {}
	for _, config in ipairs(configs) do
		covered[config.name] = true
	end
	for _, config in ipairs(discovered) do
		if not covered[config.name] then
			table.insert(configs, config)
		end
	end
	return configs
end

--- Only the configurations that start a program (no "attach")
function M.launchable(configs)
	return vim.tbl_filter(function(config)
		return config.request == "launch"
	end, configs)
end

function M.pick(configs, title, callback)
	if #configs == 0 then
		vim.notify("No run configurations found", vim.log.levels.WARN)
		return
	end
	vim.ui.select(configs, {
		prompt = title,
		format_item = function(config)
			return config.name
		end,
	}, function(config)
		if config then
			callback(config)
		end
	end)
end

--- Start a configuration with the debugger, or as a plain run: same terminal pane, no debug layout
function M.start(config, debug, filetype)
	config = vim.deepcopy(config)
	config.noDebug = not debug or nil
	require("dap").run(config, { new = true, filetype = filetype })
end

--- Open launch.json, created from `template()` (a list of JSON entries, as text) when there is none yet
function M.edit(root, template)
	local path = M.path(root)
	if vim.fn.filereadable(path) == 0 then
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		local text = '{\n  "version": "0.2.0",\n  "configurations": [\n'
			.. table.concat(template(), ",\n")
			.. "\n  ]\n}"
		vim.fn.writefile(vim.split(text, "\n"), path)
	end
	vim.cmd.edit(path)
end

--- Make a language's configurations show up in nvim-dap's own list too (<leader>dc).
--- `configs(bufnr)` is only asked in buffers of that filetype.
function M.add_provider(name, filetype, configs)
	require("dap").providers.configs[name] = function(bufnr)
		if vim.bo[bufnr].filetype ~= filetype then
			return {}
		end
		return configs(bufnr)
	end
end

return M
