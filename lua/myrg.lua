local config = {
	cmd = "rg",
}

local M = {}


M.config = config

M.setup = function(args)
	M.config = vim.tbl_deep_extend("force", M.config, args or {})
end

local function resolve_cwd(dir)
	if dir == nil or dir == "" then
		return vim.fn.getcwd()
	end
	return vim.fs.normalize(vim.fn.expand(dir))
end

local function is_absolute(path)
	return string.match(path, "^/") ~= nil or string.match(path, "^%a:[/\\]") ~= nil
end

local function absolute_path(cwd, file)
	if is_absolute(file) then
		return vim.fs.normalize(file)
	end
	return vim.fs.normalize(vim.fs.joinpath(cwd, file))
end

local function parse_match(line, cwd)
	local file, line_number, text = string.match(line, "^(.-):(%d+):(.*)$")
	if not file then
		return nil
	end
	return {filename = absolute_path(cwd, file), lnum = tonumber(line_number), text = text}
end

local function parse_file(line, cwd)
	if line == "" then
		return nil
	end
	return {filename = absolute_path(cwd, line)}
end

local function ask(questions, done)
	local answers = {}
	local function step(i)
		if i > #questions then
			done(answers)
			return
		end
		vim.ui.input({prompt = questions[i].prompt}, function(input)
			if input == nil then
				return
			end
			answers[questions[i].name] = input
			step(i + 1)
		end)
	end
	step(1)
end

local qf_statusline = "%{get(w:,'quickfix_title','')}%<%=%-14.(%l,%c%V%) %P" -- remove the [Quickfix List] from the title

local function style_qf_window()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local info = vim.fn.getwininfo(win)[1]
		if info.quickfix == 1 and info.loclist == 0 then
			vim.api.nvim_set_option_value("statusline", qf_statusline, {win = win, scope = "local"})
		end
	end
end

local generation = 0
local active = nil

local function run(args, cwd, parse)
	generation = generation + 1
	local gen = generation
	if active then
		pcall(function() active:kill(15) end)
	end

	local output = ""
	local found_result = false
	local pending = {}
	local opened = false
	local matches_printed = 0

	local function stale()
		return gen ~= generation
	end

	local function chunk_size()
		return math.max(10, matches_printed)
	end

	local function flush()
		if stale() or #pending == 0 then
			return
		end
		if not opened then
			vim.schedule(function()
				vim.fn.setqflist({}, 'r', {items = {}, title = ""}) -- empty list
				vim.cmd("copen")
				style_qf_window()
			end)
			opened = true
		end

		local tmp_pending = pending
		pending = {}
		vim.schedule(function()
			vim.fn.setqflist(tmp_pending, "a")
			vim.cmd("redraw")
		end)
		matches_printed = matches_printed + #pending
	end

	active = vim.system(args, {
		text = true,
		cwd = cwd,
		stderr = function(job_id, data, event)
			if data and not stale() then
				vim.schedule(function()
					vim.api.nvim_echo({{data, "ErrorMsg"}}, true, {})
				end)
			end
		end,
		stdout = function(job_id, data, event)
			if data and not stale() then
				output = output..data
				local location = 0
				while location do
					location = string.find(output, "\n", 1, true)
					if location then
						local line = string.gsub(string.sub(output, 1, location - 1), "\r$", "")
						output = string.sub(output, location + 1)
						local item = parse(line, cwd)
						if item then
							found_result = true
							pending[#pending + 1] = item
							if #pending >= chunk_size() then -- stops lag and allows some incremental results
								flush()
							end
						end
					end
				end
			end
		end,
	}, function(out) -- exit
		flush() -- will be in the middle of a chunk
		if not stale() then
			active = nil
		end
		if not found_result and not stale() then
			vim.schedule(function()
				vim.fn.setqflist({}, 'r', {items = {}}) -- empty list
				vim.api.nvim_echo({{"No results were found", "WarningMsg"}}, true, {})
			end)
		end
	end)
end

M.rg = function()
	ask({
		{name = "pattern", prompt = "Search Pattern: "},
		{name = "dir", prompt = "Search Directory: "},
	}, function(answers)
		if answers.pattern == "" then
			return
		end
		local cwd = resolve_cwd(answers.dir)
		local args = {M.config.cmd, "--no-heading", "--color=never", "--line-number", "--", answers.pattern}
		run(args, cwd, parse_match)
	end)
end

M.rgcwd = function(cwd_arg)
	local cwd = resolve_cwd(cwd_arg)

	ask({
		{name = "pattern", prompt = "Search Pattern: "},
	}, function(answers)
		if answers.pattern == "" then
			return
		end
		local args = {M.config.cmd, "--no-heading", "--color=never", "--line-number", "--", answers.pattern}
		run(args, cwd, parse_match)
	end)
end

M.rgff = function()
	ask({
		{name = "pattern", prompt = "File Pattern: "},
		{name = "ftype", prompt = "File Type: "},
		{name = "dir", prompt = "File Directory: "},
	}, function(answers)
		local cwd = resolve_cwd(answers.dir)
		local args = {M.config.cmd, "--no-heading", "--color=never", "--files"}
		if answers.pattern ~= "" then
			table.insert(args, "-g")
			table.insert(args, "*"..answers.pattern.."*")
		end
		if answers.ftype ~= "" then
			table.insert(args, "-t")
			table.insert(args, answers.ftype)
		end
		run(args, cwd, parse_file)
	end)
end

return M
