local M = {}

-- Adapter information
M.adapters = { "python" }
M.adapter_name = "python"

local platform = require("core.platform")

-- Helper function to find Python interpreter (project virtualenv, else the python on the PATH)
local function find_python_interpreter()
	return platform.python(vim.fn.getcwd())
end

-- Setup handler for Python configurations
M.setup_handler = function(dap)
	dap.configurations.python = {
		{
			name = "Debug current file",
			type = "debugpy",
			request = "launch",
			program = "${file}",
			pythonPath = function()
				local python = find_python_interpreter()
				if python then
					vim.notify("Using Python: " .. python, vim.log.levels.INFO)
					return python
				else
					vim.notify("Python interpreter not found", vim.log.levels.ERROR)
					return platform.system_python() or "python"
				end
			end,
			console = "integratedTerminal",
			args = function()
				local args_string = vim.fn.input("Arguments: ")
				if args_string == "" then
					return {}
				end
				return vim.split(args_string, " ")
			end,
		},
		{
			name = "Debug with custom file",
			type = "debugpy",
			request = "launch",
			program = function()
				return vim.fn.input("Path to Python file: ", platform.join(vim.fn.getcwd(), ""), "file")
			end,
			pythonPath = function()
				return find_python_interpreter() or "python"
			end,
			console = "integratedTerminal",
			args = function()
				local args_string = vim.fn.input("Arguments: ")
				if args_string == "" then
					return {}
				end
				return vim.split(args_string, " ")
			end,
		},
		{
			name = "Debug Django",
			type = "debugpy",
			request = "launch",
			program = function()
				return vim.fn.getcwd() .. "/manage.py"
			end,
			args = { "runserver", "--noreload" },
			pythonPath = function()
				return find_python_interpreter() or "python"
			end,
			console = "integratedTerminal",
			django = true,
		},
		{
			name = "Debug Flask",
			type = "debugpy",
			request = "launch",
			module = "flask",
			env = {
				FLASK_APP = function()
					return vim.fn.input("Flask app module: ", "app.py")
				end,
				FLASK_DEBUG = "1",
			},
			args = { "run", "--no-debugger", "--no-reload" },
			pythonPath = function()
				return find_python_interpreter() or "python"
			end,
			console = "integratedTerminal",
			jinja = true,
		},
		{
			name = "Debug pytest (current file)",
			type = "debugpy",
			request = "launch",
			module = "pytest",
			args = { "${file}", "-v" },
			pythonPath = function()
				return find_python_interpreter() or "python"
			end,
			console = "integratedTerminal",
		},
		{
			name = "Debug pytest (all tests)",
			type = "debugpy",
			request = "launch",
			module = "pytest",
			args = { "-v" },
			pythonPath = function()
				return find_python_interpreter() or "python"
			end,
			console = "integratedTerminal",
		},
	}
end

return M
