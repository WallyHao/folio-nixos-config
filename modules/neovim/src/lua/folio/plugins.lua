local M = {}

function M.setup(settings)
	require("nvim-web-devicons").setup()
	require("telescope").setup({
		defaults = { layout_config = { prompt_position = "top" }, sorting_strategy = "ascending" },
	})
	require("gitsigns").setup({ current_line_blame = false })
	require("which-key").setup({ preset = "modern" })
	require("nvim-autopairs").setup()
	local cmp = require("cmp")
	local snippets = require("luasnip")
	cmp.setup({
		snippet = {
			expand = function(args)
				snippets.lsp_expand(args.body)
			end,
		},
		mapping = cmp.mapping.preset.insert({
			["<C-Space>"] = cmp.mapping.complete(),
			["<C-n>"] = cmp.mapping.select_next_item(),
			["<C-p>"] = cmp.mapping.select_prev_item(),
			["<C-e>"] = cmp.mapping.abort(),
			["<CR>"] = cmp.mapping.confirm({ select = false }),
			["<Tab>"] = cmp.mapping(function(fallback)
				if cmp.visible() then
					cmp.select_next_item()
				elseif snippets.expand_or_jumpable() then
					snippets.expand_or_jump()
				else
					fallback()
				end
			end, { "i", "s" }),
			["<S-Tab>"] = cmp.mapping(function(fallback)
				if cmp.visible() then
					cmp.select_prev_item()
				elseif snippets.jumpable(-1) then
					snippets.jump(-1)
				else
					fallback()
				end
			end, { "i", "s" }),
		}),
		sources = cmp.config.sources(
			{ { name = "nvim_lsp" }, { name = "luasnip" } },
			{ { name = "path" }, { name = "buffer" } }
		),
	})
	cmp.event:on("confirm_done", require("nvim-autopairs.completion.cmp").on_confirm_done())
	local capabilities = require("cmp_nvim_lsp").default_capabilities()
	for _, server in ipairs({ "nixd", "lua_ls", "pyright", "bashls", "jsonls", "yamlls", "ts_ls" }) do
		vim.lsp.config(server, { capabilities = capabilities })
		vim.lsp.enable(server)
	end
	vim.lsp.config("lua_ls", {
		settings = { Lua = { diagnostics = { globals = { "vim" } }, telemetry = { enable = false } } },
	})
	vim.diagnostic.config({ severity_sort = true, float = { border = "rounded" }, virtual_text = false })
	require("conform").setup({
		formatters_by_ft = {
			nix = { "nixfmt" },
			lua = { "stylua" },
			python = { "ruff_format" },
			sh = { "shfmt" },
			javascript = { "prettier" },
			typescript = { "prettier" },
			javascriptreact = { "prettier" },
			typescriptreact = { "prettier" },
			json = { "prettier" },
			yaml = { "prettier" },
			markdown = { "prettier" },
			css = { "prettier" },
			html = { "prettier" },
		},
	})
	local p = settings.palette
	local normal = {
		a = { fg = p.bg0, bg = settings.accent, gui = "bold" },
		b = { fg = p.fg, bg = p.bg2 },
		c = { fg = p.fg, bg = p.bg1 },
	}
	require("lualine").setup({
		options = {
			theme = {
				normal = normal,
				insert = { a = { fg = p.bg0, bg = p.green, gui = "bold" } },
				visual = { a = { fg = p.bg0, bg = p.purple, gui = "bold" } },
				replace = { a = { fg = p.bg0, bg = p.red, gui = "bold" } },
				command = { a = { fg = p.bg0, bg = p.blue, gui = "bold" } },
				inactive = { a = { fg = p.grey1, bg = p.bg1 }, b = normal.b, c = normal.c },
			},
			globalstatus = true,
			component_separators = "",
			section_separators = { left = "", right = "" },
		},
		sections = {
			lualine_a = { "mode" },
			lualine_b = { "branch", "diff" },
			lualine_c = { { "filename", path = 1 }, "diagnostics" },
			lualine_x = { "filetype", "encoding" },
			lualine_y = { "progress" },
			lualine_z = { "location" },
		},
	})
end

return M
