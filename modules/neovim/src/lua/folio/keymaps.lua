local M = {}

function M.setup()
	local function map(mode, lhs, rhs, description)
		vim.keymap.set(mode, lhs, rhs, { silent = true, desc = description })
	end
	local telescope = require("telescope.builtin")
	map("n", "<Esc>", "<cmd>nohlsearch<CR>", "清除搜索高亮")
	map("n", "<leader>ff", telescope.find_files, "查找文件")
	map("n", "<leader>fg", telescope.live_grep, "搜索项目内容")
	map("n", "<leader>fb", telescope.buffers, "切换缓冲区")
	map("n", "<leader>fh", telescope.help_tags, "搜索帮助")
	map("n", "<leader>fr", telescope.oldfiles, "最近文件")
	map("n", "<leader>fn", function()
		local directory = vim.g.folio_notes_directory
		if vim.fn.isdirectory(directory) == 0 then
			vim.notify("笔记目录尚不存在：" .. directory, vim.log.levels.INFO)
			return
		end
		telescope.find_files({ cwd = directory, prompt_title = "笔记" })
	end, "查找笔记")
	map("n", "<leader>e", "<cmd>Explore<CR>", "浏览文件目录")
	map("n", "<leader>w", "<cmd>write<CR>", "保存文件")
	map("n", "<leader>q", "<cmd>quit<CR>", "关闭窗口")
	map("n", "<leader>cf", function()
		require("conform").format({ async = true, lsp_format = "fallback" })
	end, "格式化文件")
	map("n", "<leader>cd", vim.diagnostic.open_float, "查看诊断")
	map("n", "<leader>rn", vim.lsp.buf.rename, "重命名符号")
	map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, "代码操作")
	map("n", "gd", vim.lsp.buf.definition, "跳转定义")
	map("n", "gr", telescope.lsp_references, "查找引用")
	map("n", "K", vim.lsp.buf.hover, "悬浮文档")
	for _, direction in ipairs({ "h", "j", "k", "l" }) do
		map("n", "<C-" .. direction .. ">", "<C-w>" .. direction, "切换窗口")
	end
	map("n", "<S-h>", "<cmd>bprevious<CR>", "上一个缓冲区")
	map("n", "<S-l>", "<cmd>bnext<CR>", "下一个缓冲区")
	require("which-key").add({
		{ "<leader>f", group = "查找" },
		{ "<leader>c", group = "代码" },
	})
end

return M
