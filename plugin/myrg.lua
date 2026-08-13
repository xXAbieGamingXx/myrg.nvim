vim.api.nvim_create_user_command("Rg", function(opts)
	require("myrg").rg()
end)

vim.api.nvim_create_user_command("Rgff", function(opts)
	require("myrg").rgff()
end)

vim.api.nvim_create_user_command("Rgcwd", function(opts)
	require("myrg").rgcwd()
end, {nargs = 1})
