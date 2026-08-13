vim.api.nvim_create_user_command("Rg", function(opts)
	require("myrg").rg(opts, "")
end, { nargs = "*" })
