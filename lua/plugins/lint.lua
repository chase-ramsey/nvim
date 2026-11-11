local CONFIG = require("config")
local utils = require("utils")

---@class LinterOverrides
---@field root_markers? string[] run the linter from the nearest directory
---  containing one of these files, for linters that only read config from cwd
---@field prefer_venv? boolean use the linter in the project's virtualenv
---@field extra_args? string[] arguments placed before the linter's defaults

---Applies a repo's overrides to a linter definition, for one buffer.
---@param linter lint.Linter
---@param overrides LinterOverrides
---@param buf_dir string directory of the buffer being linted
---@param root_dir string|nil nearest directory holding one of `root_markers`
---@return lint.Linter
local function apply_overrides(linter, overrides, buf_dir, root_dir)
  local result = vim.deepcopy(linter)
  if root_dir then
    result.cwd = root_dir
  end
  if overrides.prefer_venv and type(linter.cmd) == "string" then
    result.cmd = utils.venv_tool_or_default(linter.cmd, buf_dir)
  end
  local extra_args = overrides.extra_args
  if extra_args then
    result.args = vim.list_extend(vim.deepcopy(extra_args), linter.args or {})
  end
  return result
end

---Wraps a linter so that overrides are resolved for whichever buffer is
---being linted when nvim-lint looks the linter up.
---@param linter lint.Linter|fun(): lint.Linter
---@param overrides LinterOverrides
---@return fun(): lint.Linter
local function with_overrides(linter, overrides)
  return function()
    local base = linter
    if type(base) == "function" then
      base = base()
    end
    local buf_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
    local root_dir = overrides.root_markers and vim.fs.root(buf_dir, overrides.root_markers)
    return apply_overrides(base, overrides, buf_dir, root_dir)
  end
end

return {
  "mfussenegger/nvim-lint",
  config = function()
    local lint = require("lint")
    lint.linters_by_ft = CONFIG.lint.linters_by_ft or {}

    for name, overrides in pairs(CONFIG.lint.linters or {}) do
      local linter = lint.linters[name]
      if linter then
        lint.linters[name] = with_overrides(linter, overrides)
      else
        vim.notify("nvim-lint has no linter named " .. name, vim.log.levels.WARN)
      end
    end

    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
      group = vim.api.nvim_create_augroup("nvim_lint", { clear = true }),
      callback = function()
        lint.try_lint()
      end,
    })
  end,
}
