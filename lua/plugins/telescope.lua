return {
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.6",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local ts_builtin = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", ts_builtin.find_files, { desc = "Telescope find files" })
      vim.keymap.set("n", "<leader>fg", ts_builtin.live_grep, { desc = "Telescope live grep" })
      vim.keymap.set("n", "<leader>fb", ts_builtin.buffers, { desc = "Telescope show open buffers" })
      vim.keymap.set("n", "<leader>fh", ts_builtin.help_tags, { desc = "Telescope show help files" })
    end,
  },
  {
    "nvim-telescope/telescope-ui-select.nvim",
    config = function()
      require("telescope").setup({
        extensions = {
          ["ui-select"] = {
            require("telescope.themes").get_dropdown({}),
          },
        },
      })
      require("telescope").load_extension("ui-select")
    end,
  },
}
