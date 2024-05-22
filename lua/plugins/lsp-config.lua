local venv = require("utils.venv")

local function _set_sub_venv_python_path_for_pyright_client(args)
  local client = vim.lsp.get_client_by_id(args.data.client_id)
  if client.name == "pyright" then
    local sub_venv = venv.check_for_subproject_venv_in_monorepo()

    -- If none found, return to allow default
    if not sub_venv then
      return
    end

    --[[
         If a virtual environment is found in a subproject,
         set the pythonPath for the current client's config
         to be the path to python in that venv.

         This is the method of updating the python path in
         pyright for a single client from the nvim-lspconfig
         pyright module (part of the implementation of the
         PyrightSetPythonPath command exposed there)
    ]]
    --
    client.config.settings = vim.tbl_deep_extend('force', client.config.settings,
      { python = { pythonPath = sub_venv .. "/bin/python" } })
    client.notify('workspace/didChangeConfiguration', { settings = nil })
    vim.notify("Set pythonPath to " .. client.config.settings.python.pythonPath)
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
          "tsserver",
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
      lspconfig.tsserver.setup({
        capabilities = capabilities,
      })

      vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Show LSP description" })
      vim.keymap.set("n", "<leader>gr", vim.lsp.buf.references, { desc = "List references" })
      vim.keymap.set("n", "<leader>gd", vim.lsp.buf.definition, { desc = "Go to definition" })
      vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Show code actions" })

      vim.api.nvim_create_autocmd("LspAttach", { callback = _set_sub_venv_python_path_for_pyright_client })

      vim.diagnostic.config({ virtual_text = false })
      vim.o.updatetime = 500
      vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
        group = vim.api.nvim_create_augroup("float_diagnostic", { clear = true }),
        callback = function()
          vim.diagnostic.open_float(nil, { focus = false })
        end
      })
    end,
  },
}
