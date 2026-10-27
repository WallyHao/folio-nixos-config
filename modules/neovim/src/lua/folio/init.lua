local M = {}

function M.setup(defaults)
	local config_home = vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")
	local directory = config_home .. "/folio/neovim"
	local settings = directory .. "/settings.json"
	if vim.fn.filereadable(settings) == 1 then
		defaults = vim.json.decode(table.concat(vim.fn.readfile(settings), "\n"))
	end
	vim.g.mapleader = " "
	vim.g.maplocalleader = " "
	vim.g.folio_notes_directory = vim.fn.expand(defaults.notesDirectory)
	require("folio.options").setup()
	require("folio.theme").setup(defaults)
	require("folio.plugins").setup(defaults)
	require("folio.keymaps").setup()

	local local_config = directory .. "/local.lua"
	if vim.fn.filereadable(local_config) == 1 then
		dofile(local_config)
	end
end

return M
