local toml = require("toml")

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

  return toml.parse(content)
end

local function resolve_config()
  local base_config = parse_toml_file(vim.fn.expand("$HOME") .. "/.config/nvim/lua/config/_base_config.toml", true)

  local local_configs_by_priority_desc = {
    vim.fn.expand("$HOME") .. "/.config/nvim/.nvim_config.toml",
    vim.fn.expand("$HOME") .. "/.nvim_config.toml",
    "./.nvim_config.toml",
  }

  for _, local_config_file in ipairs(local_configs_by_priority_desc) do
    local local_config_file_content = parse_toml_file(local_config_file, false)

    if not local_config_file_content then
      goto continue
    end

    for k, v in pairs(local_config_file_content) do
      base_config[k] = v
    end
    ::continue::
  end

  return base_config
end

return resolve_config()
