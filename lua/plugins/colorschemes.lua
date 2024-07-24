return {
  {
    -- Themes:
    --  * kanagawa
    --  * kanagawa-wave
    --  * kanagawa-dragon
    --  * kanagawa-lotus
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
  },
  {
    -- Themes:
    -- * tokyonight
    -- * tokyonight-storm
    -- * tokyonight-moon
    -- * tokyonight-night
    -- * tokyonight-day
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
  },
  {
    -- Themes:
    -- * cyberdream
    "scottmckendry/cyberdream.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("cyberdream").setup({ transparent = true })
    end,
  },
  {
    'navarasu/onedark.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require("onedark").setup({ style = "darker" })
    end
  }
}
