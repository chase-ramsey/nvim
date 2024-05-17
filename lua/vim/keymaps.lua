-- vim keymaps
vim.g.mapleader = " "

vim.keymap.set("n", "<leader>w", "<C-w>", { desc = "Window navigation" })

vim.keymap.set("n", "<leader>c", "<cmd>copen<CR>", { desc = "Open quick list" })
vim.keymap.set("n", "<leader>cc", "<cmd>cclose<CR>", { desc = "Close quick list" })
vim.keymap.set("n", "<leader>h", "<cmd>noh<CR>", { desc = "Clear search highlights" })
