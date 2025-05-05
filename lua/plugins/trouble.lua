return {
  "folke/trouble.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    require("trouble").setup({})

    vim.api.nvim_create_user_command("Todo", "Trouble todo filter = { buf = 0 }<cr>", {})
  end
}
