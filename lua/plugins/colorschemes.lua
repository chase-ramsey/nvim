return {
  {
    -- Themes:
    --  * kanagawa
    --  * kanagawa-wave
    --  * kanagawa-dragon * kanagawa-lotus
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
  },
  -- Themes:
  -- * catppuccin
  -- * catppuccin-latte
  -- * catppuccin-frappe
  -- * catppuccin-macchiato
  -- * catppuccin-mocha
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  -- Themes:
  -- * nightfox
  -- * dayfox
  -- * dawnfox
  -- * duskfox
  -- * nordfox
  -- * terafox
  -- * carbonfox
  {
    "EdenEast/nightfox.nvim",
    priority = 1000,
  },
  -- Themes:
  -- * everforest
  {
    "sainnhe/everforest",
    priority = 1000,
    everforest_background = "hard",
  },
  -- Themes:
  -- * papercolor
  {
    "NLKNguyen/papercolor-theme",
    priority = 1000,
  },
  -- Themes:
  -- * noctis
  {
    "iagorrr/noctishc.nvim",
    priority = 1000,
  }
}

