local handlers = require("plugins.lsp_config._handlers")
local CONFIG = require("config")


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
        },
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      lspconfig.lua_ls.setup({
        capabilities = capabilities,
      })

      lspconfig.pyright.setup({
        capabilities = capabilities,
      })

      if CONFIG and CONFIG.lsp_config.python.use_ruff then
        vim.notify("Using ruff as linter", vim.log.levels.INFO, { title = "LSP" })
        lspconfig.ruff.setup({
          capabilities = capabilities,
        })

        -- Copied from Ruff docs
        vim.api.nvim_create_autocmd("LspAttach", {
          group = vim.api.nvim_create_augroup('lsp_attach_disable_ruff_hover', { clear = true }),
          callback = function(args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if client == nil then
              return
            end
            if client.name == 'ruff' then
              -- Disable hover in favor of Pyright
              client.server_capabilities.hoverProvider = false
            end
          end,
          desc = 'LSP: Disable hover capability from Ruff',
        })
      end

      lspconfig.ts_ls.setup({
        capabilities = capabilities,
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
        end
      })

      vim.lsp.handlers["textDocument/publishDiagnostics"] = handlers.compose_lsp_diagnostics_handlers()
    end,
  },
}
