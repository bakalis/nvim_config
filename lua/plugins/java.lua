return {
	{
		-- Started from ftplugin/java.lua, see lua/lang/java.lua
		"mfussenegger/nvim-jdtls",
		lazy = true,
		dependencies = { "mfussenegger/nvim-dap" },
		init = function()
			-- JAVA_HOME follows the project of the current buffer / working directory
			require("lang.jdk").setup()
			require("lang.spring").setup()
		end,
		keys = {
			{
				"<leader>Jj",
				function()
					require("lang.jdk").select()
				end,
				desc = "Java: Select JDK",
			},
			{
				"<leader>JS",
				function()
					require("lang.spring").select()
				end,
				desc = "Java: Spring profiles",
			},
			{
				"<leader>Jp",
				function()
					require("lang.services").toggle()
				end,
				desc = "Java: Services Panel",
			},
		},
	},
	{
		-- Spring Boot language server: beans, endpoints, application.yml completion
		"JavaHello/spring-boot.nvim",
		ft = { "java", "yaml", "jproperties" },
		dependencies = { "mfussenegger/nvim-jdtls" },
		opts = {
			-- Only start in projects that actually depend on Spring Boot
			project_filter = function(root_dir)
				return require("spring_boot.util").has_spring_boot_dependency(root_dir)
			end,
		},
	},
	{
		-- Project explorer, goals, dependency analysis, archetypes
		"oclay1st/maven.nvim",
		cmd = { "Maven", "MavenInit", "MavenExec", "MavenFavorites" },
		dependencies = { "MunifTanjim/nui.nvim" },
		config = function()
			require("lang.jdk").apply()
			require("maven").setup({
				mvn_executable = require("core.platform").maven_executable(),
				default_arguments_view = { arguments = require("lang.maven").default_arguments() },
				projects_view = {
					custom_commands = {
						{
							name = "test-debug",
							description = "Run tests, waiting for a debugger on port 5005",
							cmd_args = { "-Dmaven.surefire.debug", "test" },
						},
					},
				},
			})
			require("lang.maven").setup()
		end,
		keys = {
			{
				"<leader>Ms",
				function()
					require("lang.maven").toggle("tests")
				end,
				desc = "Maven: Toggle skip tests (-DskipTests)",
			},
			{
				"<leader>MS",
				function()
					require("lang.maven").toggle("compile")
				end,
				desc = "Maven: Toggle skip test compilation (-Dmaven.test.skip)",
			},
			{
				"<leader>Mm",
				function()
					require("lang.jdk").apply()
					vim.cmd("Maven")
				end,
				desc = "Maven: Projects",
			},
			{
				"<leader>Mx",
				function()
					require("lang.jdk").apply()
					vim.cmd("MavenExec")
				end,
				desc = "Maven: Execute Goals",
			},
			{
				"<leader>Mf",
				function()
					require("lang.jdk").apply()
					vim.cmd("MavenFavorites")
				end,
				desc = "Maven: Favorites",
			},
			{
				"<leader>Mi",
				function()
					require("lang.jdk").apply()
					vim.cmd("MavenInit")
				end,
				desc = "Maven: New Project",
			},
		},
	},
}
