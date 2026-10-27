-- Adapted from Koru home/neovim.nix at b276a4a61197b7831fbbe2e44af418a3b19ae768.
-- https://github.com/WallyHao/koru-nixos-dotfiles/blob/b276a4a61197b7831fbbe2e44af418a3b19ae768/home/neovim.nix
-- Keep its restrained syntax accents; use the selected Folio palette throughout.
local M = {}

function M.setup(settings)
	vim.opt.background = settings.appearance
	vim.cmd("highlight clear")
	vim.g.colors_name = "folio"
	local p = settings.palette
	local function hl(groups, attributes)
		for group in groups:gmatch("%S+") do
			vim.api.nvim_set_hl(0, group, attributes)
		end
	end
	hl("Normal NormalNC MsgArea", { fg = p.fg, bg = p.bg0 })
	hl("NormalFloat Pmenu", { fg = p.fg, bg = p.bg1 })
	hl("FloatBorder WinSeparator", { fg = settings.accent, bg = p.bg0 })
	hl("FloatTitle PmenuSel TabLineSel", { fg = p.bg0, bg = settings.accent, bold = true })
	hl("EndOfBuffer NonText Whitespace LineNr", { fg = p.grey1 })
	hl("CursorLine", { bg = p.bg1 })
	hl("CursorLineNr", { fg = p.yellow, bold = true })
	hl("Cursor", { fg = p.bg0, bg = p.fg })
	hl("Visual", { bg = p.bg_visual })
	hl("Search IncSearch", { fg = p.bg0, bg = p.yellow })
	hl("MatchParen", { fg = p.yellow, bold = true, underline = true })
	hl("SignColumn", { bg = p.bg0 })
	hl("StatusLine", { fg = p.fg, bg = p.bg1 })
	hl("StatusLineNC TabLine TabLineFill", { fg = p.grey1, bg = p.bg1 })
	hl("Comment SpecialComment @comment", { fg = p.grey1, italic = true })
	hl("Constant Number Boolean Float @number @boolean @constant", { fg = p.yellow })
	hl("Identifier String Character @variable @string @markup.raw", { fg = p.fg })
	hl("Function Type StorageClass Structure Typedef @function @function.call @type @constructor", { fg = p.green })
	hl("Statement Conditional Repeat Label Operator Keyword Exception @keyword @operator", { fg = p.green })
	hl("PreProc Include Define Macro PreCondit Special SpecialChar @string.escape @tag.attribute", { fg = p.yellow })
	hl("Delimiter @punctuation", { fg = p.grey1 })
	hl("Directory MoreMsg @tag", { fg = p.green })
	hl("Title ModeMsg @markup.heading", { fg = p.yellow, bold = true })
	hl("Underlined @markup.link", { fg = p.blue, underline = true })
	hl("Error ErrorMsg", { fg = p.red, bold = true })
	hl("WarningMsg", { fg = p.yellow, bold = true })
	hl("Todo", { fg = p.bg0, bg = p.yellow, bold = true })
	for name, color in pairs({ Error = p.red, Warn = p.yellow, Info = p.blue, Hint = p.aqua, Ok = p.green }) do
		hl("Diagnostic" .. name, { fg = color })
		hl("DiagnosticUnderline" .. name, { sp = color, undercurl = true })
	end
	for name, colors in pairs({
		Add = { p.green, p.bg_green },
		Change = { p.blue, p.bg_blue },
		Delete = { p.red, p.bg_red },
		Text = { p.yellow, p.bg_yellow },
	}) do
		hl("Diff" .. name, { fg = colors[1], bg = colors[2] })
	end
	for name, color in pairs({ Add = p.green, Change = p.yellow, Delete = p.red }) do
		hl("GitSigns" .. name, { fg = color })
	end
	hl(
		"TelescopeBorder TelescopePromptBorder TelescopeResultsBorder TelescopePreviewBorder",
		{ fg = settings.accent, bg = p.bg0 }
	)
	hl("TelescopeSelection", { bg = p.bg_visual, bold = true })
end

return M
