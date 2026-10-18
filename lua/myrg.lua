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
		return vim.fs.normalize(vim.fn.getcwd())
	end
	return vim.fs.normalize(vim.fn.expand(dir))
end

local function verify_cwd(cwd)
	local stat = vim.uv.fs_stat(cwd)
	if not stat then
		vim.api.nvim_echo({{"Directory does not exist: "..cwd, "WarningMsg"}}, true, {})
		return false
	end
	if stat.type ~= "directory" then
		vim.api.nvim_echo({{"Not a directory: "..cwd, "WarningMsg"}}, true, {})
		return false
	end
	return true
end

local function is_absolute(path)
	return string.match(path, "^/") ~= nil or string.match(path, "^%a:[/\\]") ~= nil
end

local function needs_normalize(file)
	return string.find(file, "\\", 1, true) ~= nil
		or string.find(file, "//", 1, true) ~= nil
		or string.find("/"..file.."/", "/%.%.?/") ~= nil -- . or .. segment
end

local function absolute_path(cwd, file)
	if is_absolute(file) then
		return vim.fs.normalize(file)
	end
	if not needs_normalize(file) then -- rg paths are usually fine
		local sep = string.sub(cwd, -1) == "/" and "" or "/"
		return cwd..sep..file
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

local generation = 0
local active = nil

local function run(args, cwd, parse, pattern)
	if not verify_cwd(cwd) then
		return
	end

	generation = generation + 1
	local gen = generation
	if active then
		pcall(function() active:kill(15) end)
	end

	local output = ""
	local found_result = false
	local opened = false
	local qflist = {}
	local ndefs = 0 -- defs at start of list
	local written = 0
	local dirty = false -- replace next sync
	local written_defs = 0 -- ndefs as of the last write
	local pending = false -- a flush is scheduled

	local function stale()
		return gen ~= generation
	end

	local function chunk_size()
		return math.max(10, written)
	end

	local function flush()
		pending = false
		if stale() then
			return
		end
		local replace = dirty or not opened
		if not replace and #qflist == written then
			return
		end
		local first = not opened

		if replace then
			local what = {items = qflist, title = ""}
			if not first then
				local idx = vim.fn.getqflist({idx = 0}).idx
				if idx > written_defs then
					idx = idx + ndefs - written_defs
				end
				what.idx = idx
			end
			vim.fn.setqflist({}, "r", what)
		else
			vim.fn.setqflist(vim.list_slice(qflist, written + 1, #qflist), "a")
		end

		dirty = false
		written = #qflist
		written_defs = ndefs
		opened = true

		if first then
			vim.cmd("copen")
		end
		vim.cmd("redraw")
	end

	local function sync()
		if pending or stale() then
			return
		end
		pending = true
		vim.schedule(flush)
	end

	local function test_definition(line)
		if not pattern or pattern == "" or type(line) ~= "string" then
			return false
		end

		if (string.gsub(line, "[ \t]+", "")) == "}"..pattern..";" then
			return true
		end

		local stripped = string.match(line, "^([^(]+)") -- everything before the first (
		if not stripped then
			return false
		end

		if string.find(stripped, "=", 1, true) then -- an = before ( means assignment
			return false
		end

		local words = {}
		for word in string.gmatch(stripped, "%S+") do
			words[#words + 1] = word
		end

		if words[1] == "if" or words[1] == "else" or words[1] == "elif" then
			return false
		end

		for i = 2, #words do -- must be preceded by a type/keyword
			if words[i] == pattern then
				return true
			end
		end

		return false
	end

	local function consume(line)
		local item = parse(line, cwd)
		if not item then
			return
		end
		found_result = true
		if test_definition(item.text) then
			ndefs = ndefs + 1
			table.insert(qflist, ndefs, item)
			dirty = true
		else
			qflist[#qflist + 1] = item
		end
		if #qflist - written >= chunk_size() then -- incremental results without the lag
			sync()
		end
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
				local start = 1
				while true do
					local location = string.find(output, "\n", start, true)
					if not location then
						break
					end
					local line = string.gsub(string.sub(output, start, location - 1), "\r$", "")
					start = location + 1
					consume(line)
				end
				output = string.sub(output, start)
			end
		end,
	}, function(out) -- exit
		if not stale() then
			if output ~= "" then -- last line had no trailing newline
				consume((string.gsub(output, "\r$", "")))
				output = ""
			end
			sync() -- will be in the middle of a chunk
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
		run(args, cwd, parse_match, answers.pattern)
	end)
end

M.rgcwd = function(cwd_arg)
	local cwd = resolve_cwd(cwd_arg)
	if not verify_cwd(cwd) then
		return
	end

	ask({
		{name = "pattern", prompt = "Search Pattern: "},
	}, function(answers)
		if answers.pattern == "" then
			return
		end
		local args = {M.config.cmd, "--no-heading", "--color=never", "--line-number", "--", answers.pattern}
		run(args, cwd, parse_match, answers.pattern)
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
