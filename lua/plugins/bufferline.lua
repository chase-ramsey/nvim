return {
  "akinsho/bufferline.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function ()
    require("bufferline").setup{}
    vim.keymap.set("n", "<leader>bp", ":BufferLinePick<CR>", { desc = ":BufferLinePick" })
  end
}
