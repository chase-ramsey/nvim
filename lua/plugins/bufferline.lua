return {
  {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local bufferline = require("bufferline")
      bufferline.setup({
        options = {
          style_preset = bufferline.style_preset.no_italic,
        },
      })
      vim.keymap.set("n", "<leader>p", ":BufferLinePick<CR>", { desc = ":BufferLinePick" })
      vim.keymap.set("n", "<C-j>", ":BufferLineCycleNext<CR>", { desc = ":BufferLineCycleNext" })
      vim.keymap.set("n", "<C-k>", ":BufferLineCyclePrev<CR>", { desc = ":BufferLineCyclePrev" })
    end,
  },
  {
    "ojroques/nvim-bufdel",
    config = function()
      require("bufdel").setup()
      vim.keymap.set("n", "<leader>q", ":BufDel<CR>", { desc = ":BufDel (delete buffer)" })
    end,
  },
}
