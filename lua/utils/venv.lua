local function check_for_subproject_venv_in_monorepo()
  local git_root = io.popen("git rev-parse --show-toplevel", "r"):read()
  if not git_root then
    return
  end

  -- If there is a virtual environment in the project root
  -- return to allow default
  if vim.fn.isdirectory(git_root .. "/.venv") == 1 then
    return
  end

  -- Otherwise, search parent directories in the current buffer's
  -- file path for a virtual environment, and return the first one found
  for parent_dir in vim.fs.parents(vim.api.nvim_buf_get_name(0)) do
    if vim.fn.isdirectory(parent_dir .. "/.venv") == 1 then
      return parent_dir .. "/.venv"
    end

    -- Don't go any farther up than the git root
    if parent_dir == git_root then
      break
    end
  end
end

return {
  check_for_subproject_venv_in_monorepo = check_for_subproject_venv_in_monorepo,
}
