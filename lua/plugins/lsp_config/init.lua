local CONFIG = require("config")
local handlers = require("plugins.lsp_config._handlers")
local utils = require("utils")

local python_config = CONFIG.lsp_config.python
local use_pyrefly = python_config.type_checker == "pyrefly"

---Builds an LSP `cmd` that prefers the copy of `tool` pinned in the project's
---virtualenv, so the server matches the version the project's CI runs.
---@param tool string
---@param args string[]
---@return fun(dispatchers: vim.lsp.rpc.Dispatchers, config: vim.lsp.ClientConfig): vim.lsp.rpc.PublicClient
local function venv_tool_cmd(tool, args)
  return function(dispatchers, config)
    local root_dir = config.root_dir or vim.fn.getcwd()
    local cmd = vim.list_extend({ utils.venv_tool_or_default(tool, root_dir) }, args)
    return vim.lsp.rpc.start(cmd, dispatchers, { cwd = root_dir, env = config.cmd_env })
  end
end

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
          "taplo",
        },
        -- pyright stays installed, but must not start alongside pyrefly.
        automatic_enable = { exclude = use_pyrefly and { "pyright" } or {} },
      })
    end,
  },
  {
    -- Installs the non-LSP tools that conform runs (see conform.lua).
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-tool-installer").setup({
        ensure_installed = {
          "stylua",
          "prettier",
        },
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      local type_checker = use_pyrefly and "pyrefly" or "pyright"
      local servers = { "lua_ls", type_checker, "ts_ls", "ruff", "taplo" }
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

      vim.lsp.config("ruff", {
        cmd = venv_tool_cmd("ruff", { "server" }),
        init_options = {
          settings = { lint = { enable = python_config.ruff_lint } },
        },
      })

      if use_pyrefly then
        -- pyrefly is not installed through Mason: projects pin their own
        -- version, and its diagnostics should match their CI.
        vim.lsp.config("pyrefly", { cmd = venv_tool_cmd("pyrefly", { "lsp" }) })
        vim.lsp.enable("pyrefly")
      end

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
