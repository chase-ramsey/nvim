return {
  "j-hui/fidget.nvim",
  opts = {
    notification = {
      override_vim_notify = true,
    }
  },
  config = function()
    require("fidget").setup({
      notification = {
        override_vim_notify = true,
      }
    })

    vim.api.nvim_set_keymap("n", "<C-f>h", "<cmd>Fidget history<cr>", { desc = "Show Fidget history" })
  end,
}
