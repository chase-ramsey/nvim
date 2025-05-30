require("vim.global_opts")
require("vim.keymaps")

local CONFIG = require("config")

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end

vim.opt.rtp:prepend(lazypath)

-- Initialize plugins
require("lazy").setup("plugins")
vim.cmd("set termguicolors")
vim.cmd("colorscheme " .. CONFIG.colorschemes.theme)
