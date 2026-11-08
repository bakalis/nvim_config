-- Spring profile picker, like the "Active profiles" field of IntelliJ's Spring Boot run configuration.
--   * finds the profiles of a project from its configuration files (application-<profile>.yml/.properties,
--     bootstrap-<profile>.*, and documents with `spring.config.activate.on-profile`)
--   * you pick one or several in a popup, the choice is remembered per project
--   * it is applied to everything started from Neovim: Run/Debug configurations get
--     SPRING_PROFILES_ACTIVE and `mvn spring-boot:run` gets -Dspring-boot.run.profiles
-- A profile that a run configuration or command sets itself (env, vmArgs, args, -D flag) always wins.
local platform = require("core.platform")

local M = {}

local OPTION = "spring_profiles"

-- folders that never contain the configuration of the project
local skipped_folders = { target = true, build = true, out = true, node_modules = true, [".git"] = true, [".idea"] = true, [".gradle"] = true, [".mvn"] = true, dist = true }

local file_patterns = {
	"^application%-(.+)%.ya?ml$",
	"^application%-(.+)%.properties$",
	"^bootstrap%-(.+)%.ya?ml$",
	"^bootstrap%-(.+)%.properties$",
}

local function java()
	return require("lang.java")
end

--- Root of the project of the current buffer, the working directory outside Java files
local function current_root()
	local name = vim.api.nvim_buf_get_name(0)
	if vim.bo.filetype == "java" and name ~= "" then
		return java().find_root(name)
	end
	return java().find_root(platform.join(vim.fn.getcwd(), "."))
end

--- Folder of the Maven/Gradle module a configuration file belongs to
local function module_of(path)
	return path:match("^(.*)/src/main/resources") or path:match("^(.*)/src/test/resources") or vim.fs.dirname(path)
end

--- Module of the current buffer, nil if it is not in one
local function current_module()
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		return nil
	end
	local found = vim.fs.find({ "pom.xml", "build.gradle", "build.gradle.kts" }, { path = vim.fs.dirname(name), upward = true, limit = 1 })[1]
	return found and vim.fs.dirname(found) or nil
end

---------------------------------------------------------------------------
-- Finding the profiles of a project
---------------------------------------------------------------------------

local cache = {}

--- Profile names mentioned by a configuration file's own documents (`on-profile: dev`, `spring.profiles=dev`)
local function profiles_inside(path)
	local names = {}
	for _, line in ipairs(vim.fn.readfile(path, "", 400)) do
		local value = line:match("^%s*on%-profile:%s*(.+)$")
			or line:match("^%s+profiles:%s*([^%s#][^#]*)$")
			or line:match("^spring%.config%.activate%.on%-profile%s*[=:]%s*(.+)$")
			or line:match("^spring%.profiles%s*[=:]%s*(.+)$")
		if value then
			value = value:gsub("!%s*[%w_%-]+", "") -- "cloud & !local" only names cloud
			for name in value:gmatch("[%w_%-]+") do
				table.insert(names, name)
			end
		end
	end
	return names
end

--- All profiles of the project under `root`: { { name, files, modules, tests_only }, ... }.
--- Cheap enough for big multi-module repositories, build folders are not entered.
function M.discover(root)
	local cached = cache[root]
	if cached and vim.uv.now() - cached.time < 10000 then
		return cached.profiles
	end

	local by_name = {}
	local function add(name, path)
		local entry = by_name[name] or { name = name, files = {}, modules = {}, tests_only = true }
		table.insert(entry.files, path)
		entry.modules[module_of(path)] = true
		if not path:find("/src/test/", 1, true) then
			entry.tests_only = false
		end
		by_name[name] = entry
	end

	local scanned = 0
	local iterator = vim.fs.dir(root, {
		depth = 10,
		skip = function(directory)
			return not skipped_folders[directory:match("[^/]+$") or directory] -- false means "do not enter"
		end,
	})
	for relative, kind in iterator do
		local base = relative:match("[^/]+$")
		if kind == "file" and (base:match("^application.*%.ya?ml$") or base:match("^application.*%.properties$") or base:match("^bootstrap.*%.ya?ml$")) then
			local path = platform.join(root, relative)
			for _, pattern in ipairs(file_patterns) do
				local name = base:match(pattern)
				if name then
					add(name, path)
				end
			end
			scanned = scanned + 1
			if scanned <= 600 then
				for _, name in ipairs(profiles_inside(path)) do
					add(name, path)
				end
			end
		end
	end

	local profiles = vim.tbl_values(by_name)
	table.sort(profiles, function(a, b)
		return a.name < b.name
	end)
	cache[root] = { time = vim.uv.now(), profiles = profiles }
	return profiles
end

---------------------------------------------------------------------------
-- The chosen profiles
---------------------------------------------------------------------------

--- Profiles chosen for the project, a list of names (empty when none)
function M.active(root)
	local value = platform.project_option(root or current_root(), OPTION)
	return type(value) == "table" and value or {}
end

local function set_active(root, names)
	platform.set_project_option(root, OPTION, #names > 0 and names or nil)
end

--- Comma separated, the form every Spring setting takes
function M.active_text(root)
	return table.concat(M.active(root), ",")
end

--- Label for the statusline, kept per buffer so redraws stay cheap
function M.update_label(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local ok, root = pcall(current_root)
	if not ok then
		return
	end
	local text = M.active_text(root)
	vim.b[buf].spring_profiles_label = text ~= "" and ("profiles: " .. text) or ""
end

function M.statusline()
	return vim.b.spring_profiles_label or ""
end

---------------------------------------------------------------------------
-- Applying them
---------------------------------------------------------------------------

local function mentions_profile(value)
	if type(value) == "table" then
		value = table.concat(value, " ")
	end
	return type(value) == "string" and value:find("spring.profiles.active", 1, true) ~= nil
end

--- A run configuration that already says which profile to use is left alone
local function sets_profile_itself(config)
	local env = config.env
	return (type(env) == "table" and env.SPRING_PROFILES_ACTIVE ~= nil) or mentions_profile(config.vmArgs) or mentions_profile(config.args)
end

--- Root of the project a run configuration belongs to
local function config_root(config)
	local cwd = config.cwd
	if type(cwd) == "string" and cwd ~= "" and not cwd:find("${", 1, true) and vim.fn.isdirectory(cwd) == 1 then
		return java().find_root(platform.join(cwd, "."))
	end
	return current_root()
end

--- Run/Debug: give the application SPRING_PROFILES_ACTIVE
function M.setup_dap()
	local dap = require("dap")
	dap.listeners.on_config["spring-profiles"] = function(config)
		if config.type ~= "java" or config.request ~= "launch" or not config.mainClass or sets_profile_itself(config) then
			return config
		end
		local profiles = M.active_text(config_root(config))
		if profiles ~= "" then
			config = vim.deepcopy(config)
			config.env = vim.tbl_extend("force", type(config.env) == "table" and config.env or {}, { SPRING_PROFILES_ACTIVE = profiles })
		end
		return config
	end
end

--- Maven: `spring-boot:run` runs with the chosen profiles. Other goals, tests included, are left alone.
function M.maven_arguments(args, cwd)
	local runs_application = false
	for _, argument in ipairs(args) do
		runs_application = runs_application or argument:match("spring%-boot:run$") ~= nil or argument:match("spring%-boot:start$") ~= nil
		if argument:find("spring-boot.run.profiles", 1, true) then
			return args
		end
	end
	if not runs_application then
		return args
	end
	local root = cwd and java().find_root(platform.join(cwd, ".")) or current_root()
	local profiles = M.active_text(root)
	if profiles == "" then
		return args
	end
	args = vim.list_slice(args)
	table.insert(args, "-Dspring-boot.run.profiles=" .. profiles)
	return args
end

---------------------------------------------------------------------------
-- The popup
---------------------------------------------------------------------------

local function parse_names(text)
	local names = {}
	for name in (text or ""):gmatch("[%w_%-]+") do
		if not vim.tbl_contains(names, name) then
			table.insert(names, name)
		end
	end
	return names
end

local function finish(root, names)
	set_active(root, names)
	M.update_label()
	vim.notify(#names > 0 and ("Spring profiles: " .. table.concat(names, ", ") .. "  (Run/Debug and spring-boot:run)") or "Spring profiles: none, the application's own defaults apply")
end

local function type_names(root)
	vim.ui.input({ prompt = "Spring profiles (comma separated): ", default = M.active_text(root) }, function(text)
		if text ~= nil then
			finish(root, parse_names(text))
		end
	end)
end

--- Rows of the popup: profiles that are known, then the two special entries
local function build_items(root)
	local active, module = M.active(root), current_module()
	local items = {}
	for _, profile in ipairs(M.discover(root)) do
		local count = vim.tbl_count(profile.modules)
		local notes = { count == 1 and "1 module" or (count .. " modules") }
		if module and profile.modules[module] then
			table.insert(notes, "this module")
		end
		if profile.tests_only then
			table.insert(notes, "tests only")
		end
		table.insert(items, {
			kind = "profile",
			name = profile.name,
			in_module = module ~= nil and profile.modules[module] == true,
			display = string.format("%s %-22s %s", vim.tbl_contains(active, profile.name) and "●" or " ", profile.name, table.concat(notes, " · ")),
		})
	end
	-- profiles of this module, then the ones used in real code, then the rest
	table.sort(items, function(a, b)
		if a.in_module ~= b.in_module then
			return a.in_module
		end
		return a.name < b.name
	end)
	table.insert(items, { kind = "type", display = "  ✎ Type profile names…", name = "" })
	table.insert(items, { kind = "clear", display = "  ✕ None: use the application's own defaults", name = "" })
	return items
end

function M.select(root)
	root = root or current_root()
	local items = build_items(root)
	local title = "Spring profiles · " .. vim.fn.fnamemodify(root, ":t")

	local ok, pickers = pcall(require, "telescope.pickers")
	if not ok then
		-- no telescope: single choice
		vim.ui.select(items, {
			prompt = title,
			format_item = function(item)
				return item.display
			end,
		}, function(item)
			if not item then
				return
			elseif item.kind == "type" then
				type_names(root)
			else
				finish(root, item.kind == "clear" and {} or { item.name })
			end
		end)
		return
	end

	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local active = M.active(root)

	-- the profiles that are active now start out selected (once the list is filled), Tab changes that
	local preselected = false
	local function preselect(current)
		if preselected then
			return
		end
		preselected = true
		for index, item in ipairs(items) do
			if item.kind == "profile" and vim.tbl_contains(active, item.name) then
				pcall(function()
					current:add_selection(current:get_row(index))
				end)
			end
		end
	end

	pickers
		.new(require("telescope.themes").get_dropdown({ previewer = false, width = 0.6 }), {
			prompt_title = title .. "   (Tab: select several, Enter: apply)",
			finder = finders.new_table({
				results = items,
				entry_maker = function(item)
					return { value = item, display = item.display, ordinal = item.name ~= "" and item.name or item.display }
				end,
			}),
			sorter = conf.generic_sorter({}),
			on_complete = { preselect },
			attach_mappings = function(prompt_buffer)
				actions.select_default:replace(function()
					local current = action_state.get_current_picker(prompt_buffer)
					local multi = current:get_multi_selection()
					local highlighted = action_state.get_selected_entry()
					actions.close(prompt_buffer)

					local chosen = {}
					for _, entry in ipairs(#multi > 0 and multi or { highlighted }) do
						if entry.value.kind == "type" then
							return type_names(root)
						elseif entry.value.kind == "clear" then
							return finish(root, {})
						end
						table.insert(chosen, entry.value.name)
					end
					finish(root, chosen)
				end)
				return true
			end,
		})
		:find()
end

--- Keep the statusline label current when entering Java buffers
function M.setup()
	vim.api.nvim_create_autocmd({ "BufEnter" }, {
		group = vim.api.nvim_create_augroup("spring-profiles", { clear = true }),
		callback = function(event)
			if vim.bo[event.buf].filetype == "java" then
				M.update_label(event.buf)
			end
		end,
	})
end

return M
