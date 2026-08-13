local config = {
	cmd = "rg",
}

local M = {}


M.config = config

M.setup = function(args)
	M.config = vim.tbl_deep_extend("force", M.config, args or {})
end

M.rg = function(opts, cwd_arg)
	local cwd = ""
	if(#cwd_arg == 0) then
		cwd = vim.fn.getcwd()
	else
		cwd = cwd_arg
	end

	args = {M.config.cmd}

	for word in string.gmatch(opts.args, "%S+") do
		table.insert(args, word)
	end

	if(#opts.args > 0) then
		vim.fn.jobstart(args, {
			stderr_buffered = true,
			on_stderr = function(job_id, data, event)
				vim.api.nvim_echo({{data, "ErrorMsg"}}, true, {})
			end,
			on_exit = function(job_id, data, event)

			end,
			on_stdout = function(job_id, data, event)
				print(data)
			end,
			cwd = cwd,
		})

		local result = vim.fn.system(M.config.cmd.." "..opts.args)
		print(result)
	end
end

return M
