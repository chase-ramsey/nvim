local CONFIG = require("config")

return {
  "stevearc/conform.nvim",
  config = function()
    local conform = require("conform")
    local formatters = {
      javascript = { "prettier" },
      typescript = { "prettier" },
      lua = { "stylua" },
      sql = { "sqlfluff" },
    }

    if CONFIG and CONFIG.lsp_config.python.use_ruff then
      formatters.python = { "ruff_fix", "ruff_format", "ruff_organize_imports" }
    else
      formatters.python = { "black", "isort" }
    end

    conform.setup({
      formatters_by_ft = formatters,
    })

    vim.api.nvim_create_autocmd("BufWritePre", {
      pattern = "*",
      callback = function(args)
        conform.format({ bufnr = args.buf })
      end,
    })
  end,
}
