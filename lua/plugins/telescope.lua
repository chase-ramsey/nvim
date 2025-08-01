local CONFIG = require("config")

return {
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.6",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local ts_config = require("telescope.config")
      if CONFIG and CONFIG.telescope then
        ts_config.set_defaults({ file_ignore_patterns = CONFIG.telescope.file_ignore_patterns or {} })
      end

      local ts_builtin = require("telescope.builtin")

      vim.keymap.set("n", "<leader>ff", ts_builtin.find_files, { desc = "Telescope find files" })
      vim.keymap.set("n", "<leader>fg", ts_builtin.live_grep, { desc = "Telescope live grep" })
      vim.keymap.set("n", "<leader>fb", ts_builtin.buffers, { desc = "Telescope show open buffers" })
      vim.keymap.set("n", "<leader>fh", ts_builtin.help_tags, { desc = "Telescope show help files" })
      vim.keymap.set("n", "<leader>fr", ts_builtin.resume, { desc = "Telescope show last live grep results" })
      vim.keymap.set("n", "<leader>fs", ts_builtin.grep_string, { desc = "Telescope grep for string under cursor" })

      local function recent_files()
        ts_builtin.oldfiles({ cwd_only = true, include_current_session = true })
      end

      vim.keymap.set("n", "<leader>fo", recent_files, { desc = "Telescope show recent files" })
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
