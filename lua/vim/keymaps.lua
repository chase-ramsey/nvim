-- vim keymaps
vim.g.mapleader = " "

vim.keymap.set("n", "<leader>wj", "<C-w>j<CR>", { desc = "Focus on window to above current" })
vim.keymap.set("n", "<leader>wk", "<C-w>k<CR>", { desc = "Focus on window to below current" })
vim.keymap.set("n", "<leader>wh", "<C-w>h<CR>", { desc = "Focus on window to left of current" })
vim.keymap.set("n", "<leader>wl", "<C-w>l<CR>", { desc = "Focus on window to right of current" })
