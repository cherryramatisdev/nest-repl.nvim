local M = {}

-- Configuration
local config = {
	repl_command = "npx nest repl",
	debug = false,
	terminal_width = 80, -- Width of the terminal split
	terminal_position = "right", -- 'left' or 'right'
	keybindings = {
		start_repl = "<localleader>snr",
		load_method = "<localleader>em",
		load_method_to_var = "<localleader>etv",
	},
}

-- State to track the REPL terminal
local state = {
	repl_terminal = nil,
	repl_bufnr = nil,
	repl_job_id = nil,
}

-- Setup function
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})

	-- Set up keybindings
	vim.keymap.set("n", config.keybindings.start_repl, function()
		M.start_repl()
	end, { desc = "Start NestJS REPL" })

	vim.keymap.set("v", config.keybindings.load_method, function()
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")
		M.load_methods_to_repl(start_line, end_line)
	end, { desc = "Load selected method to NestJS REPL" })

	vim.keymap.set("n", config.keybindings.load_method, function()
		local start_line, end_line = M.find_current_method()
		if start_line and end_line then
			M.load_methods_to_repl(start_line, end_line)
		else
			vim.notify("No method found at cursor position", vim.log.levels.WARN)
		end
	end, { desc = "Load current method to NestJS REPL" })

	vim.keymap.set("v", config.keybindings.load_method_to_var, function()
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")
		M.load_method_to_variable(start_line, end_line)
	end, { desc = "Load selected method to variable in NestJS REPL" })

	vim.keymap.set("n", config.keybindings.load_method_to_var, function()
		local start_line, end_line = M.find_current_method()
		if start_line and end_line then
			M.load_method_to_variable(start_line, end_line)
		else
			vim.notify("No method found at cursor position", vim.log.levels.WARN)
		end
	end, { desc = "Load current method to variable in NestJS REPL" })
end

-- Find the root of the NestJS project
function M.find_nest_root()
	local current_dir = vim.fn.expand("%:p:h")
	local nest_config = vim.fn.findfile("nest-cli.json", current_dir .. ";")

	if nest_config == "" then
		return nil
	end

	return vim.fn.fnamemodify(nest_config, ":h")
end

-- Start or focus the REPL terminal
function M.start_repl()
	local project_root = M.find_nest_root()
	if not project_root then
		vim.notify("Not in a NestJS project directory", vim.log.levels.ERROR)
		return
	end

	-- If terminal exists, just focus it
	if state.repl_terminal and vim.api.nvim_win_is_valid(state.repl_terminal) then
		vim.api.nvim_set_current_win(state.repl_terminal)
		return
	end

	-- Create a new terminal based on position config
	if config.terminal_position == "left" then
		vim.cmd("leftabove vsplit")
	else
		vim.cmd("rightbelow vsplit")
	end

	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_width(win, config.terminal_width) -- Set terminal width

	-- Start the REPL
	local job_id = vim.fn.termopen(string.format("cd %s && %s", project_root, config.repl_command), {
		on_exit = function()
			state.repl_terminal = nil
			state.repl_bufnr = nil
			state.repl_job_id = nil
		end,
	})

	-- Store terminal info
	state.repl_terminal = win
	state.repl_bufnr = buf
	state.repl_job_id = job_id

	-- Set terminal options
	vim.api.nvim_buf_set_option(buf, "buflisted", false)
	vim.api.nvim_buf_set_option(buf, "buftype", "terminal")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")

	-- Add keymaps
	vim.keymap.set("t", "<C-w>q", function()
		vim.api.nvim_win_close(win, true)
		state.repl_terminal = nil
		state.repl_bufnr = nil
		state.repl_job_id = nil
	end, { buffer = buf, silent = true })
end

-- Send command to REPL terminal
function M.send_to_repl(cmd)
	if not state.repl_terminal or not vim.api.nvim_win_is_valid(state.repl_terminal) then
		vim.notify("REPL terminal not found. Start it with :NestReplStart", vim.log.levels.ERROR)
		return
	end

	-- Switch to terminal window
	local current_win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(state.repl_terminal)

	-- Send the command using chansend
	vim.fn.chansend(state.repl_job_id, cmd .. "\n")

	-- Switch back to previous window
	vim.api.nvim_set_current_win(current_win)
end

-- Extract class name from file content
function M.extract_class_name(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	-- Match class declaration
	local class_pattern = "class%s+(%w+)"
	local class_name = content:match(class_pattern)

	return class_name
end

-- Main function to load methods into REPL
function M.load_methods_to_repl(start_line, end_line)
	local bufnr = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)

	-- Check if file is TypeScript/JavaScript
	if not filename:match("%.ts$") and not filename:match("%.js$") then
		vim.notify("Not a TypeScript/JavaScript file", vim.log.levels.ERROR)
		return
	end

	-- Get class name
	local class_name = M.extract_class_name(bufnr)
	if not class_name then
		vim.notify("Could not find class name in file", vim.log.levels.ERROR)
		return
	end

	-- Get selected text using line numbers
	local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
	local selected_text = table.concat(lines, "\n")

	-- Extract method name
	local method_name = M.extract_method_name(selected_text)
	if not method_name then
		vim.notify("Could not extract method name from selection", vim.log.levels.ERROR)
		return
	end

	-- Send method to REPL with correct syntax
	M.send_to_repl(string.format("await $(%s).%s()", class_name, method_name))
end

-- Extract method name from selected text
function M.extract_method_name(text)
	-- Match method name with async keyword
	local pattern = "async%s+(%w+)%s*%("
	local method_name = text:match(pattern)

	if not method_name then
		-- Try without async keyword
		pattern = "(%w+)%s*%("
		method_name = text:match(pattern)
	end

	-- Skip constructor and private methods
	if method_name and method_name ~= "constructor" and not method_name:match("^_") then
		return method_name
	end

	return nil
end

-- Find the method boundaries around the cursor
function M.find_current_method()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Find method start (looking for method declaration)
	local start_line = cursor_line
	while start_line > 0 do
		local line = lines[start_line]
		if line:match("^%s*async%s+%w+%s*%(") or line:match("^%s*%w+%s*%(") then
			break
		end
		start_line = start_line - 1
	end

	-- Find method end (looking for closing brace)
	local end_line = cursor_line
	local brace_count = 0
	while end_line <= #lines do
		local line = lines[end_line]
		brace_count = brace_count + (line:gsub("{", ""):len() - line:len()) -- count opening braces
		brace_count = brace_count - (line:gsub("}", ""):len() - line:len()) -- count closing braces

		if brace_count == 0 and end_line > start_line then
			break
		end
		end_line = end_line + 1
	end

	if start_line > 0 and end_line <= #lines then
		return start_line, end_line
	end

	return nil, nil
end

-- Load method into a variable in REPL
function M.load_method_to_variable(start_line, end_line)
	local bufnr = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)

	-- Check if file is TypeScript/JavaScript
	if not filename:match("%.ts$") and not filename:match("%.js$") then
		vim.notify("Not a TypeScript/JavaScript file", vim.log.levels.ERROR)
		return
	end

	-- Get class name
	local class_name = M.extract_class_name(bufnr)
	if not class_name then
		vim.notify("Could not find class name in file", vim.log.levels.ERROR)
		return
	end

	-- Get selected text using line numbers
	local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
	local selected_text = table.concat(lines, "\n")

	-- Extract method name
	local method_name = M.extract_method_name(selected_text)
	if not method_name then
		vim.notify("Could not extract method name from selection", vim.log.levels.ERROR)
		return
	end

	-- Send method to REPL with variable assignment
	M.send_to_repl(string.format("let %s = await $(%s).%s()", method_name, class_name, method_name))
end

-- Create commands
vim.api.nvim_create_user_command("NestReplStart", function()
	M.start_repl()
end, {})

vim.api.nvim_create_user_command("NestReplLoad", function(opts)
	-- Check if we have a range
	if not opts.range then
		vim.notify("Please select a method in visual mode", vim.log.levels.WARN)
		return
	end

	M.load_methods_to_repl(opts.line1, opts.line2)
end, { range = true })

return M

