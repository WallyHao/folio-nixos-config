local M = {}

function M.setup()
	local opt = vim.opt
	opt.termguicolors = true
	opt.number = true
	opt.relativenumber = true
	opt.cursorline = true
	opt.signcolumn = "yes"
	opt.wrap = false
	opt.scrolloff = 6
	opt.sidescrolloff = 6
	opt.expandtab = true
	opt.shiftwidth = 2
	opt.tabstop = 2
	opt.smartindent = true
	opt.ignorecase = true
	opt.smartcase = true
	opt.splitbelow = true
	opt.splitright = true
	opt.updatetime = 250
	opt.timeoutlen = 400
	opt.completeopt = { "menu", "menuone", "noselect" }
	opt.clipboard = "unnamedplus"
	opt.undofile = true
	opt.swapfile = false
	opt.backup = false
	opt.laststatus = 3
	opt.showmode = false
	opt.fillchars = { eob = " " }

	local group = vim.api.nvim_create_augroup("FolioEditor", { clear = true })
	vim.api.nvim_create_autocmd("TextYankPost", {
		group = group,
		callback = function()
			vim.hl.on_yank()
		end,
	})
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		callback = function(event)
			-- Parsers ship in the Nix closure; unsupported file types use Vim syntax.
			pcall(vim.treesitter.start, event.buf)
		end,
	})
end

return M
