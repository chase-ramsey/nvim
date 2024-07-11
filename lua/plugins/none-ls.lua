return {
  {
    "nvimtools/none-ls.nvim",
    config = function()
      local null_ls = require("null-ls")

      null_ls.setup({
        sources = {
          -- Lua
          null_ls.builtins.formatting.stylua,
          -- Python
          null_ls.builtins.formatting.isort.with({ command = "/Users/chase/.local/bin/isort" }),
          null_ls.builtins.formatting.black.with({ command = "/Users/chase/.local/bin/black" }),
          -- Javascript
          null_ls.builtins.formatting.prettier,
        },
        debug = true,
      })

      vim.keymap.set("n", "<leader>gf", vim.lsp.buf.format, { desc = "Lint/format file" })
      vim.api.nvim_create_autocmd("BufWrite", { callback = vim.lsp.buf.format })
    end,
  },
}
