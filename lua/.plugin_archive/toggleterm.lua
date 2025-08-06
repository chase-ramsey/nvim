return {
  "akinsho/toggleterm.nvim",
  config = function()
    local toggleterm = require("toggleterm")
    toggleterm.setup()
    vim.keymap.set(
      "n",
      "<leader>tth",
      ":ToggleTerm direction=horizontal dir=git_dir<CR>",
      { desc = "Toggle horizontal terminal" }
    )
    vim.keymap.set(
      "n",
      "<C-k>",
      ":ToggleTerm direction=float dir=git_dir<CR>",
      { desc = "Toggle floating terminal" }
    )

    -- This makes it easier to enter normal mode
    -- from terminal mode
    vim.keymap.set("t", "<esc>", "<C-\\><C-N>")
  end,
}
