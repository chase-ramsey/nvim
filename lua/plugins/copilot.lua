return {
  "github/copilot.vim",
  config = function()
    vim.keymap.set("i", "<S-Tab>", 'copilot#Accept("\\<CR>")', {
      expr = true,
      replace_keycodes = false,
    })
    vim.g.copilot_no_tab_map = true
    vim.keymap.set("i", "<C-L>", "<Plug>(copilot-accept-word)")

    vim.g.copilot_settings = {
      selectedCompletionModel = "claude-opus-4-6",
    }
  end,
}
