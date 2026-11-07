return {
	{
		-- Started from ftplugin/java.lua, see lua/lang/java.lua
		"mfussenegger/nvim-jdtls",
		lazy = true,
		dependencies = { "mfussenegger/nvim-dap" },
		keys = {
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
			require("lang.java").ensure_java_home()
			local mvnw = vim.fn.getcwd() .. "/mvnw"
			require("maven").setup({
				mvn_executable = vim.fn.executable(mvnw) == 1 and mvnw or "mvn",
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
		end,
		keys = {
			{ "<leader>Mm", "<cmd>Maven<cr>", desc = "Maven: Projects" },
			{ "<leader>Mx", "<cmd>MavenExec<cr>", desc = "Maven: Execute Goals" },
			{ "<leader>Mf", "<cmd>MavenFavorites<cr>", desc = "Maven: Favorites" },
			{ "<leader>Mi", "<cmd>MavenInit<cr>", desc = "Maven: New Project" },
		},
	},
}
