-- Taken from this helpful SO answer: https://stackoverflow.com/a/27914619
local function compose(...)
  local fnchain = ...
  local function recurse(i, ...)
    if i == #fnchain then
      return fnchain[i](...)
    end
    return recurse(i + 1, fnchain[i](...))
  end
  return function(...)
    return recurse(1, ...)
  end
end

---Returns `start_dir` followed by each of its ancestors, nearest first.
---@param start_dir string
---@return string[]
local function dir_and_ancestors(start_dir)
  local dirs = { start_dir }
  for parent in vim.fs.parents(start_dir) do
    table.insert(dirs, parent)
  end
  return dirs
end

---Finds `tool` in the nearest `.venv/bin` at or above `start_dir`.
---A virtualenv that does not contain the tool is skipped, so a tool pinned
---only in a monorepo's root virtualenv is still found from a nested project.
---@param tool string
---@param start_dir string
---@return string|nil path absolute path of the executable, or nil if none exists
local function find_venv_tool(tool, start_dir)
  for _, dir in ipairs(dir_and_ancestors(start_dir)) do
    local candidate = vim.fs.joinpath(dir, ".venv", "bin", tool)
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
  return nil
end

---Returns the virtualenv copy of `tool` when one exists, else the bare name
---so that it resolves through PATH.
---@param tool string
---@param start_dir string
---@return string
local function venv_tool_or_default(tool, start_dir)
  return find_venv_tool(tool, start_dir) or tool
end

---Builds the command that runs a repo's pre-commit hooks on one file.
---@param file string
---@param has_mise boolean whether `mise` is on PATH; repos that install prek
---  through mise only expose it via `mise exec`
---@return string[]
local function prek_command(file, has_mise)
  local run = { "prek", "run", "--files", file }
  if has_mise then
    return vim.list_extend({ "mise", "exec", "--" }, run)
  end
  return run
end

return {
  compose = compose,
  find_venv_tool = find_venv_tool,
  venv_tool_or_default = venv_tool_or_default,
  prek_command = prek_command,
}
