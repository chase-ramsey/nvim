-- Global vim settings

vim.o.cursorline = true -- highlight the screen line of the cursor
vim.o.number = true     -- show line numbers
vim.o.expandtab = true  -- use spaces for tabs
vim.o.tabstop = 2       -- length of a tab defined in spaces
vim.o.softtabstop = 2   -- length in spaces inserted on press of <Tab> key
vim.o.shiftwidth = 2    -- number of spaces for an indent

vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.html*",
  callback = function()
    vim.cmd("setlocal filetype=html")
  end
})
