local handlers = require("plugins.lsp_config._handlers")

return {
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",
          "pyright",
          "ts_ls",
          "ruff",
        },
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      local servers = { "lua_ls", "pyright", "ts_ls", "ruff" }
      for _, server in ipairs(servers) do
        vim.lsp.config(server, {
          capabilities = capabilities,
        })
      end

      -- In this monorepo, pyproject.toml (which contains [tool.pyright] settings
      -- including venvPath) must take priority over the root pyrightconfig.json.
      vim.lsp.config("pyright", {
        root_markers = { "pyproject.toml", "pyrightconfig.json" },
      })

      vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Show LSP description" })
      vim.keymap.set("n", "<leader>gr", vim.lsp.buf.references, { desc = "List references" })
      vim.keymap.set("n", "<leader>gd", vim.lsp.buf.definition, { desc = "Go to definition" })
      vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Show code actions" })

      vim.diagnostic.config({ virtual_text = false })
      vim.o.updatetime = 500
      vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
        group = vim.api.nvim_create_augroup("float_diagnostic", { clear = true }),
        callback = function()
          vim.diagnostic.open_float(nil, { focus = false })
        end,
      })

      vim.lsp.handlers["textDocument/publishDiagnostics"] = handlers.compose_lsp_diagnostics_handlers()
    end,
  },
}
