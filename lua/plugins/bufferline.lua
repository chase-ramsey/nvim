return {
  {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("bufferline").setup {}
      vim.keymap.set("n", "<leader>bb", ":BufferLinePick<CR>", { desc = ":BufferLinePick" })
    end
  },
  {
    "ojroques/nvim-bufdel",
    config = function ()
      require("bufdel").setup()
      vim.keymap.set("n", "<leader>q", ":BufDel<CR>", { desc = ":BufDel (delete buffer)" })
    end
  }
}
