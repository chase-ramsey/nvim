local utils = require("utils")

-- Prefer the ruff pinned in the project's virtualenv, so formatting matches
-- what the project's own hooks and CI produce.
local function ruff_command(_, ctx)
  return utils.venv_tool_or_default("ruff", ctx.dirname)
end

return {
  "stevearc/conform.nvim",
  config = function()
    local conform = require("conform")

    conform.setup({
      formatters_by_ft = {
        javascript = { "prettier" },
        typescript = { "prettier" },
        lua = { "stylua" },
        sql = { "sqlfluff" },
        python = { "ruff_organize_imports", "ruff_format" },
      },
      formatters = {
        ruff_organize_imports = { command = ruff_command },
        ruff_format = { command = ruff_command },
      },
    })

    vim.api.nvim_create_autocmd("BufWritePre", {
      pattern = "*",
      callback = function(args)
        conform.format({ bufnr = args.buf })
      end,
    })
  end,
}
