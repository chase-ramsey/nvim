-- vim keymaps
vim.g.mapleader = " "

vim.keymap.set("n", "<leader>w", "<C-w>", { desc = "Window navigation" })

vim.keymap.set("n", "<leader>c", "<cmd>copen<CR>", { desc = "Open quick list" })
vim.keymap.set("n", "<leader>cc", "<cmd>cclose<CR>", { desc = "Close quick list" })
vim.keymap.set("n", "<leader>h", "<cmd>noh<CR>", { desc = "Clear search highlights" })

-- Run the repo's pre-commit hooks (prek) on the current file.
local function prek_current_file()
  local utils = require("utils")
  local file = vim.api.nvim_buf_get_name(0)
  local root = vim.fs.root(0, ".pre-commit-config.yaml")
  if file == "" or not root then
    vim.notify("prek: no .pre-commit-config.yaml above this file", vim.log.levels.WARN)
    return
  end

  vim.cmd("silent update")
  vim.notify("prek: running on " .. vim.fs.basename(file))
  local command = utils.prek_command(file, vim.fn.executable("mise") == 1)
  vim.system(
    command,
    { cwd = root, text = true },
    vim.schedule_wrap(function(result)
      vim.cmd("checktime") -- hooks may have rewritten the file
      if result.code == 0 then
        vim.notify("prek: passed")
        return
      end
      local output = vim.split((result.stdout or "") .. (result.stderr or ""), "\n")
      vim.cmd("botright new")
      vim.bo.buftype = "nofile"
      vim.bo.bufhidden = "wipe"
      vim.api.nvim_buf_set_lines(0, 0, -1, false, output)
    end)
  )
end

vim.api.nvim_create_user_command("Prek", prek_current_file, { desc = "Run prek hooks on the current file" })
vim.keymap.set("n", "<leader>k", prek_current_file, { desc = "Run prek hooks on the current file" })
