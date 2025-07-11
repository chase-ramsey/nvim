local toml = require("toml")

local cached_config = nil

local function parse_toml_file(file, fail)
  local f = io.open(file, "r")

  if not f then
    if fail then
      error(file .. " is missing!")
    end
    return nil
  end

  local content = f:read("*a")
  f:close()

  local ok, result = pcall(toml.parse, content)
  if not ok then
    error("Failed to parse TOML in " .. file .. ": " .. result)
  end
  return result
end

local function resolve_config()
  if cached_config then
    return cached_config
  end

  local base_config = parse_toml_file(
    vim.fs.normalize(
      vim.fn.expand("$HOME") .. "/.config/nvim/lua/config/_base_config.toml"
    ), true
  ) or {}

  local local_configs_by_priority_desc = {
    vim.fs.normalize(vim.fn.expand("$HOME") .. "/.config/nvim/.nvim_config.toml"),
    vim.fs.normalize(vim.fn.expand("$HOME") .. "/.nvim_config.toml"),
    vim.fs.normalize("./.nvim_config.toml"),
  }

  for _, local_config_file in ipairs(local_configs_by_priority_desc) do
    local local_config_file_content = parse_toml_file(local_config_file, false)

    if not local_config_file_content then
      goto continue
    end

    base_config = vim.tbl_deep_extend("force", base_config, local_config_file_content)
    ::continue::
  end

  cached_config = base_config
  return base_config
end

return resolve_config()
