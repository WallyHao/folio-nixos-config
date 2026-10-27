-- Run against the packaged editor with disposable HOME/XDG directories only.
local ok, message = xpcall(function()
	assert(vim.v.errmsg == "", vim.v.errmsg)
	assert(vim.g.colors_name == "folio")
	assert(vim.o.termguicolors and vim.o.number and vim.o.undofile)
	assert(vim.fn.maparg("<Space>ff", "n") ~= "")
	assert(vim.fn.maparg("<Space>cf", "n") ~= "")
	local config_home = vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")
	local settings_file = config_home .. "/folio/neovim/settings.json"
	local settings = vim.json.decode(table.concat(vim.fn.readfile(settings_file), "\n"))
	assert(vim.o.background == settings.appearance)
	local expected = tonumber(settings.palette.bg0:sub(2), 16)
	assert(vim.api.nvim_get_hl(0, { name = "Normal" }).bg == expected)
	assert(vim.g.folio_notes_directory == vim.fn.expand(settings.notesDirectory))

	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	vim.fn.writefile({ "[project]", 'name = "editor-test"', 'version = "0.0.0"' }, directory .. "/pyproject.toml")
	vim.fn.writefile({ "value=1", "print( value )" }, directory .. "/sample.py")
	vim.cmd.edit(vim.fn.fnameescape(directory .. "/sample.py"))
	local parser = vim.treesitter.get_parser(0, "python")
	assert(parser:parse()[1]:root():type() == "module")
	require("conform").format({ timeout_ms = 10000 })
	assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "value = 1")
	assert(require("cmp").get_config().sources[1].name == "nvim_lsp")
	assert(require("lualine").get_config().options.globalstatus)

	require("telescope.builtin").find_files({ cwd = directory })
	local picker = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf())
	assert(vim.wait(5000, function()
		return picker.manager and picker.manager:num_results() >= 2
	end))
	require("telescope.actions").close(vim.api.nvim_get_current_buf())
	if vim.env.FOLIO_TEST_LSP == "1" then
		assert(
			vim.wait(20000, function()
				return #vim.lsp.get_clients({ name = "pyright", bufnr = 0 }) > 0
			end),
			"Python LSP did not attach"
		)
		local client = vim.lsp.get_clients({ name = "pyright", bufnr = 0 })[1]
		assert(
			vim.wait(20000, function()
				return client.initialized
			end),
			"Python LSP did not initialize"
		)
		local response = client:request_sync("textDocument/hover", {
			textDocument = { uri = vim.uri_from_bufnr(0) },
			position = { line = 0, character = 1 },
		}, 20000, 0)
		assert(response and response.result, "Python LSP hover failed")
	end
	for _, client in ipairs(vim.lsp.get_clients()) do
		client:stop(true)
	end
	assert(vim.v.errmsg == "", vim.v.errmsg)
end, debug.traceback)
if not ok then
	vim.api.nvim_err_writeln(message)
	vim.cmd("cquit 1")
end
