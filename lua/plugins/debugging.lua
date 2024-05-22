return {
  "mfussenegger/nvim-dap",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "rcarriga/nvim-dap-ui",
    "mfussenegger/nvim-dap-python"
  },
  config = function()
    local dap = require("dap")
    vim.keymap.set("n", "<C-b>", dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
    vim.keymap.set("n", "<C-d>", dap.continue, { desc = "Debug continue" })
    vim.keymap.set("n", "<Leader>s", dap.step_over, { desc = "Debug step over" })
    vim.keymap.set("n", "<Leader>j", dap.step_into, { desc = "Debug step into" })
    vim.keymap.set("n", "<Leader>k", dap.step_out, { desc = "Debug step out" })

    local dappy = require("dap-python")
    dappy.setup("~/.local/share/nvim/mason/packages/debugpy/venv/bin/python")

    local function _wrap_test_method_with_opts()
      dappy.test_method({ config = { justMyCode = false } })
    end

    local function _wrap_test_class_with_opts()
      dappy.test_class({ config = { justMyCode = false } })
    end

    dappy.test_runner = "pytest"
    vim.keymap.set("n", "<Leader>dm", _wrap_test_method_with_opts, { desc = "Python: test method (debug)" })
    vim.keymap.set("n", "<Leader>dc", _wrap_test_class_with_opts, { desc = "Python: test class (debug)" })

    local dapui = require("dapui")
    dapui.setup()

    vim.keymap.set("n", "<Leader>dd", dapui.close, { desc = "close dap-ui" })
    dap.listeners.before.attach.dapui_config = function()
      dapui.open()
    end
    dap.listeners.before.launch.dapui_config = function()
      dapui.open()
    end
  end
}
