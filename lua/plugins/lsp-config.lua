local function _check_for_subproject_venv_in_monorepo(args)
  local client = vim.lsp.get_client_by_id(args.data.client_id)
  if client.name == "pyright" then
    -- If there is a virtual environment in the project root
    -- return to allow default
    local git_root = io.popen("git rev-parse --show-toplevel", "r"):read()
    if not git_root then
      return
    end

    if vim.fn.isdirectory(git_root .. "/.venv") == 1 then
      return
    end

    -- Otherwise, search parent directories in the current buffer's
    -- file path for a virtual environment
    local sub_venv
    for parent_dir in vim.fs.parents(vim.api.nvim_buf_get_name(0)) do
      if vim.fn.isdirectory(parent_dir .. "/.venv") == 1 then
        sub_venv = parent_dir .. "/.venv"
        break
      end

      -- Don't go any farther up than the git root
      if parent_dir == git_root then
        break
      end
    end

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
    print("Set pythonPath to " .. client.config.settings.python.pythonPath)
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

      vim.api.nvim_create_autocmd("LspAttach", { callback = _check_for_subproject_venv_in_monorepo })

      vim.diagnostic.config({ virtual_text = false })
      vim.o.updatetime = 500
      vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
        group = vim.api.nvim_create_augroup("float_diagnostic", { clear = true }),
        callback = function ()
          vim.diagnostic.open_float(nil, {focus=false})
        end
      })
    end,
  },
}
