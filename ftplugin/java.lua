-- Runs for every Java buffer. jdtls is started here rather than through
-- vim.lsp.enable, see lua/lang/java.lua
require("lang.java").attach()
