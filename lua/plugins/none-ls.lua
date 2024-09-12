return {
  {
    "nvimtools/none-ls.nvim",
    config = function()
      local null_ls = require("null-ls")

      null_ls.setup({
        opts = {
          default_timeout = 10000,
          debounce = 1000,
        },
        sources = {
          -- Lua
          null_ls.builtins.formatting.stylua,
          -- Python
          null_ls.builtins.formatting.isort.with({ prefer_local = ".venv/bin" }),
          null_ls.builtins.formatting.black.with({ prefer_local = ".venv/bin" }),
          -- Javascript
          null_ls.builtins.formatting.prettier,
        },
        debug = true,
      })

      vim.keymap.set("n", "<leader>p", vim.lsp.buf.format, { desc = "Lint/format file" })
      -- vim.api.nvim_create_autocmd("BufWritePre", { callback = vim.lsp.buf.format })
    end,
  },
}
