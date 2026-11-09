-- Project JDK: pick it from a popup, apply it to Maven and the language server, show it in the
-- statusline. The OS specific work (finding JDKs, reading project files, the saved choice) is in
-- core.platform, this file is the user interface around it.
local platform = require("core.platform")

local M = {}

--- Root of the project the current buffer belongs to, the working directory outside Java files
local function current_root()
	local java = require("lang.java")
	local name = vim.api.nvim_buf_get_name(0)
	if vim.bo.filetype == "java" and name ~= "" then
		return java.find_root(name)
	end
	return java.find_root(platform.join(vim.fn.getcwd(), "."))
end

local function short(path)
	return vim.fn.fnamemodify(path, ":~")
end

--- "Corretto 17.0.13"
local function describe(jdk)
	return string.format("%s %s", jdk.vendor or "JDK", jdk.version or jdk.major)
end

--- Label shown in the statusline, kept per buffer so redraws stay cheap
function M.update_label(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local ok, root = pcall(current_root)
	if not ok then
		return
	end
	local jdk = platform.project_jdk(root)
	local declared = platform.declared_java(root)
	local home = vim.env.JAVA_HOME
	local major = jdk and jdk.major
	if not major and home and home ~= "" then
		for _, candidate in ipairs(platform.jdks()) do
			if platform.same_path(candidate.path, home) then
				major = candidate.major
			end
		end
	end
	local label = major and ("JDK " .. major) or ""
	-- the active JDK is not the version the project asks for
	if major and declared and declared.major ~= major and jdk == nil then
		label = label .. " (project wants " .. declared.major .. ")"
	end
	vim.b[buf].jdk_label = label
end

function M.statusline()
	return vim.b.jdk_label or ""
end

--- Set JAVA_HOME for the project of the current context and refresh the statusline
function M.apply(root)
	root = root or current_root()
	local jdk, source = platform.use_project_jdk(root)
	M.update_label()
	return jdk, source
end

--- Restart jdtls with the same configuration. nvim-jdtls' own restart() still calls the deprecated
--- vim.lsp.start_client(), so this uses vim.lsp.start().
function M.restart_server()
	for _, client in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do
		local buffers = vim.tbl_keys(client.attached_buffers)
		local config = client.config
		client:stop()
		vim.wait(30000, function()
			return vim.lsp.get_client_by_id(client.id) == nil
		end)
		for _, buffer in ipairs(buffers) do
			if vim.api.nvim_buf_is_valid(buffer) then
				vim.lsp.start(config, { bufnr = buffer })
			end
		end
	end
end

local function restart_language_server(root)
	for _, client in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do
		if client.root_dir and platform.same_path(client.root_dir, root) then
			if vim.fn.confirm("Restart the Java language server to use the new JDK?", "&Yes\n&No", 1) == 1 then
				M.restart_server()
			end
			return
		end
	end
end

--- The popup: every JDK found, "Add JDK from folder", and "Automatic" (follow the project's own files)
function M.select(root)
	root = root or current_root()
	local effective = vim.env.JAVA_HOME
	local declared = platform.declared_java(root)
	local items = {}
	for _, jdk in ipairs(platform.jdks()) do
		table.insert(items, { kind = "jdk", jdk = jdk })
	end
	table.insert(items, { kind = "add" })
	table.insert(items, { kind = "auto" })

	local title = "Project JDK · " .. vim.fn.fnamemodify(root, ":t")
	if declared then
		title = title .. "  (asks for Java " .. declared.major .. " in " .. declared.source .. ")"
	end

	vim.ui.select(items, {
		prompt = title,
		format_item = function(item)
			if item.kind == "add" then
				return "   + Add JDK from folder…"
			elseif item.kind == "auto" then
				return "   ↺ Automatic: follow the project's files"
			end
			local jdk = item.jdk
			local current = effective and platform.same_path(jdk.path, effective) and "●" or " "
			local wanted = declared and declared.major == jdk.major and "✓" or " "
			return string.format("%s%s %-4s %-24s %s", current, wanted, jdk.major, describe(jdk), short(jdk.path))
		end,
	}, function(item)
		if not item then
			return
		end
		if item.kind == "add" then
			vim.ui.input({ prompt = "JDK folder: ", completion = "dir" }, function(path)
				if not path or path == "" then
					return
				end
				local jdk, reason = platform.add_custom_jdk(path)
				if not jdk then
					vim.notify("Not a JDK: " .. reason, vim.log.levels.ERROR)
					return
				end
				vim.notify("Added " .. describe(jdk) .. ", pick it from the list")
				vim.schedule(function()
					M.select(root)
				end)
			end)
			return
		end

		platform.set_project_jdk(root, item.kind == "jdk" and item.jdk.path or nil)
		local jdk, source = M.apply(root)
		if item.kind == "auto" then
			vim.notify(jdk and ("Following the project: " .. describe(jdk) .. " (" .. source .. ")") or "Following the machine default JDK")
		else
			local mismatch = declared and declared.major ~= item.jdk.major
			vim.notify(
				"Project JDK: " .. describe(item.jdk) .. (mismatch and ("  (project asks for Java " .. declared.major .. ")") or ""),
				mismatch and vim.log.levels.WARN or vim.log.levels.INFO
			)
		end
		restart_language_server(root)
	end)
end

--- Follow the project: set JAVA_HOME when you enter a Java buffer or change directory
--- Run/Debug: start the application on the project's JDK. Without this jdtls picks the runtime that
--- matches the project's compiler level (a Java 17 project runs on 17 even when 27 was chosen).
function M.setup_dap()
	local dap = require("dap")
	local platform = require("core.platform")
	dap.listeners.on_config["project-jdk"] = function(config)
		if config.type ~= "java" or config.request ~= "launch" or not config.mainClass or config.javaExec then
			return config
		end
		local cwd = config.cwd
		local root
		if type(cwd) == "string" and cwd ~= "" and not cwd:find("${", 1, true) and vim.fn.isdirectory(cwd) == 1 then
			root = require("lang.java").find_root(platform.join(cwd, "."))
		else
			root = current_root()
		end
		local jdk = root and platform.project_jdk(root)
		if jdk then
			config = vim.deepcopy(config)
			config.javaExec = platform.java_executable(jdk.path)
		end
		return config
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("project-jdk", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
		group = group,
		callback = function(event)
			if event.event == "DirChanged" or vim.bo[event.buf].filetype == "java" then
				M.apply()
			end
		end,
	})
end

return M
