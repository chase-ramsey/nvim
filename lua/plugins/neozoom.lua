return {
  "nyngwang/NeoZoom.lua",
  config = function()
    require("neo-zoom").setup()
    vim.keymap.set('n', '<leader><CR>', function() vim.cmd('NeoZoomToggle') end, { silent = true, nowait = true })
  end,
}
