local M = {}

-- Adapter information
M.adapters = { "codelldb" }
M.adapter_name = "codelldb"

-- Helper function to find Rust workspace root
local function find_rust_workspace()
	local current_file = vim.fn.expand("%:p:h")
	local root = vim.fn.findfile("Cargo.toml", current_file .. ";")
	if root ~= "" then
		return vim.fn.fnamemodify(root, ":h")
	end
	return vim.fn.getcwd()
end

-- Helper function to get Rust binary name from Cargo.toml
local function get_rust_binary()
	local workspace = find_rust_workspace()
	local cargo_toml = workspace .. "/Cargo.toml"

	if vim.fn.filereadable(cargo_toml) == 0 then
		vim.notify("Cargo.toml not found", vim.log.levels.ERROR)
		return nil
	end

	local lines = vim.fn.readfile(cargo_toml)
	local package_name = nil

	for _, line in ipairs(lines) do
		local name = line:match('^name%s*=%s*"([^"]+)"')
		if name then
			package_name = name
			break
		end
	end

	if not package_name then
		vim.notify("Could not find package name in Cargo.toml", vim.log.levels.ERROR)
		return nil
	end

	local bin_dir = workspace .. "/src/bin"
	if vim.fn.isdirectory(bin_dir) == 1 then
		local binaries = vim.fn.glob(bin_dir .. "/*.rs", false, true)
		if #binaries > 1 then
			local choices = {}
			for _, bin_path in ipairs(binaries) do
				local bin_name = vim.fn.fnamemodify(bin_path, ":t:r")
				table.insert(choices, bin_name)
			end
			table.insert(choices, 1, package_name)

			vim.ui.select(choices, {
				prompt = "Select binary to debug:",
			}, function(choice)
				if choice then
					package_name = choice
				end
			end)
		end
	end

	return workspace .. "/target/debug/" .. package_name
end

-- Helper function to build Rust project
local function build_rust_project()
	local workspace = find_rust_workspace()
	vim.notify("Building Rust project...", vim.log.levels.INFO)

	local build_cmd = string.format("cd %s && cargo build 2>&1", workspace)
	local output = vim.fn.system(build_cmd)

	if vim.v.shell_error ~= 0 then
		vim.notify("Build failed:\n" .. output, vim.log.levels.ERROR)
		return false
	end

	vim.notify("Build successful!", vim.log.levels.INFO)
	return true
end

-- Setup handler for Rust configurations
M.setup_handler = function(dap)
	dap.configurations.rust = {
		{
			name = "Debug (auto-build)",
			type = "codelldb",
			request = "launch",
			program = function()
				if not build_rust_project() then
					return nil
				end
				local binary = get_rust_binary()
				if not binary then
					vim.notify("Could not detect binary", vim.log.levels.ERROR)
					return nil
				end
				return binary
			end,
			cwd = "${workspaceFolder}",
			stopOnEntry = false,
			args = function()
				local args_string = vim.fn.input("Arguments: ")
				return vim.split(args_string, " ")
			end,
		},
		{
			name = "Debug (no build)",
			type = "codelldb",
			request = "launch",
			program = function()
				local binary = get_rust_binary()
				if not binary then
					vim.notify("Could not detect binary", vim.log.levels.ERROR)
					return nil
				end
				return binary
			end,
			cwd = "${workspaceFolder}",
			stopOnEntry = false,
			args = function()
				local args_string = vim.fn.input("Arguments: ")
				return vim.split(args_string, " ")
			end,
		},
		{
			name = "Debug tests",
			type = "codelldb",
			request = "launch",
			program = function()
				local workspace = find_rust_workspace()
				vim.notify("Building tests...", vim.log.levels.INFO)
				local build_cmd = string.format("cd %s && cargo test --no-run 2>&1", workspace)
				local output = vim.fn.system(build_cmd)

				if vim.v.shell_error ~= 0 then
					vim.notify("Test build failed:\n" .. output, vim.log.levels.ERROR)
					return nil
				end

				local test_binary = output:match("Executable [^(]*%(([^)]+)%)")
				if test_binary then
					vim.notify("Test build successful!", vim.log.levels.INFO)
					return test_binary
				else
					vim.notify("Could not find test binary", vim.log.levels.ERROR)
					return nil
				end
			end,
			cwd = "${workspaceFolder}",
			stopOnEntry = false,
			args = function()
				local test_name = vim.fn.input("Test name (or empty for all): ")
				if test_name ~= "" then
					return { test_name, "--exact" }
				end
				return {}
			end,
		},
		{
			name = "Debug (manual path)",
			type = "codelldb",
			request = "launch",
			program = function()
				return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
			end,
			cwd = "${workspaceFolder}",
			stopOnEntry = false,
			args = function()
				local args_string = vim.fn.input("Arguments: ")
				return vim.split(args_string, " ")
			end,
		},
	}
end

return M
