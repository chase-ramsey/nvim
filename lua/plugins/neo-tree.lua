return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    opts = {
      window = { position = "right" },
      filesystem = {
        filtered_items = {
          visible = true,
          never_show = {
            ".git",
          }
        },
      }
    },
    config = function()
      vim.keymap.set('n', '<C-n>', ':Neotree filesystem reveal toggle right<CR>')
    end
  }
}

