return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = {
          theme = "papercolor_light",
        },
        sections = {
          lualine_c = {
            { "filename", newfile_status = true, path = 1, color = { fg = "#ffffff" } },
            "diff",
          },
        },
      })
    end,
  },
}
