local CONFIG = require("config")

return {
  {
    "nvimtools/none-ls.nvim",
    config = function()
      local null_ls = require("null-ls")

      sources = {
        -- Lua
        null_ls.builtins.formatting.stylua,
        -- Javascript
        null_ls.builtins.formatting.prettier,
      }

      if CONFIG and not CONFIG.lsp_config.python.use_ruff then
        table.insert(sources, null_ls.builtins.formatting.isort)
        table.insert(sources, null_ls.builtins.formatting.black)
      end


      null_ls.setup({
        opts = {
          default_timeout = 10000,
          debounce = 1000,
        },
        sources = sources,
        debug = true,
      })

      vim.keymap.set("n", "<leader>p", vim.lsp.buf.format, { desc = "Lint/format file" })
      -- vim.api.nvim_create_autocmd("BufWritePre", { callback = vim.lsp.buf.format })
    end,
  },
}
