-- "Skip tests" for Maven started from Neovim, like IntelliJ's Toggle 'Skip Tests' Mode.
-- Two flavours, only one can be on:
--   -DskipTests              tests are compiled but not run
--   -Dmaven.test.skip=true   tests are not even compiled
-- The flags live in maven.nvim's own "default arguments" list (press g in its project view to see them
-- and toggle them there too). maven.nvim only adds that list to commands started from its project view
-- and favorites, so commands typed into :MavenExec are covered here as well.
local M = {}

local SKIP_TESTS = "-DskipTests"
local SKIP_COMPILE = "-Dmaven.test.skip"

-- phases that run tests, anything else (dependency:tree, clean, ...) is left alone
local test_phases = { test = true, ["integration-test"] = true, verify = true, package = true, install = true, deploy = true }

--- The default arguments handed to maven.nvim's setup
function M.default_arguments()
	return {
		{ arg = SKIP_TESTS, enabled = false },
		{ arg = SKIP_COMPILE, value = "true", enabled = false },
	}
end

local function arguments()
	return require("maven.config").options.default_arguments_view.arguments
end

local function find(arg)
	for _, argument in ipairs(arguments()) do
		if argument.arg == arg then
			return argument
		end
	end
end

local function as_text(argument)
	return argument.arg .. (argument.value and ("=" .. argument.value) or "")
end

--- "tests", "compile" or nil: what is currently skipped
function M.mode()
	if not package.loaded["maven.config"] then
		return nil
	end
	local skip, compile = find(SKIP_TESTS), find(SKIP_COMPILE)
	if compile and compile.enabled then
		return "compile"
	end
	return skip and skip.enabled and "tests" or nil
end

function M.statusline()
	local mode = M.mode()
	return mode == "tests" and "skip tests" or (mode == "compile" and "skip test compile" or "")
end

--- Switch one flavour on or off ("tests" or "compile"); turning one on turns the other off
function M.toggle(flavour)
	require("lazy").load({ plugins = { "maven.nvim" } })
	local wanted, other = find(flavour == "compile" and SKIP_COMPILE or SKIP_TESTS), find(flavour == "compile" and SKIP_TESTS or SKIP_COMPILE)
	if not (wanted and other) then
		vim.notify("maven.nvim has no skip-tests arguments configured", vim.log.levels.ERROR)
		return
	end
	wanted.enabled = not wanted.enabled
	if wanted.enabled then
		other.enabled = false
	end
	vim.notify(wanted.enabled and ("Maven: tests skipped (" .. as_text(wanted) .. ")") or "Maven: tests run again")
	vim.cmd("redrawstatus")
end

--- Add the enabled default arguments to every command that runs tests, also typed ones
function M.setup()
	local console = require("maven.utils.console")
	if console.skip_tests_wrapped then
		return
	end
	console.skip_tests_wrapped = true
	local execute = console.execute_command
	console.execute_command = function(command, args, show_output, callback, cwd)
		args = require("lang.spring").maven_arguments(args, cwd) -- spring-boot:run gets the chosen profiles
		local runs_tests = false
		for _, argument in ipairs(args) do
			runs_tests = runs_tests or test_phases[argument] == true
		end
		if runs_tests then
			args = vim.list_slice(args)
			for _, argument in ipairs(arguments()) do
				local text = as_text(argument)
				if argument.enabled == true and not vim.tbl_contains(args, text) then
					table.insert(args, text)
				end
			end
		end
		return execute(command, args, show_output, callback, cwd)
	end
end

return M
