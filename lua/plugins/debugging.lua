return {
  "mfussenegger/nvim-dap",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "rcarriga/nvim-dap-ui",
    "mfussenegger/nvim-dap-python"
  },
  config = function()
    local dap = require("dap")
    vim.keymap.set("n", "<Leader>db", dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
    vim.keymap.set("n", "<Leader>dc", dap.continue, { desc = "Debug continue" })
    vim.keymap.set("n", "<Leader>ds", dap.step_over, { desc = "Debug step over" })
    vim.keymap.set("n", "<Leader>dj", dap.step_into, { desc = "Debug step into" })
    vim.keymap.set("n", "<Leader>dk", dap.step_out, { desc = "Debug step out" })

    local dappy = require("dap-python")
    dappy.setup("~/.local/share/nvim/mason/packages/debugpy/venv/bin/python")
    dappy.test_runner = "pytest"
    vim.keymap.set("n", "<Leader>dm", dappy.test_method, { desc = "Python: test method (debug)" })

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
