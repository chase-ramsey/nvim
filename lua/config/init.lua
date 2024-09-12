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
  local config = {}
  local base_config = parse_toml_file(vim.fn.expand("$HOME") .. "/.config/nvim/lua/config/_base_config.toml", true)

  -- TODO: resolve multiple local configs
  local local_config = parse_toml_file(vim.fn.expand("$HOME") .. "/.config/nvim/local_config.toml", false)

  for k, v in pairs(base_config) do
    config[k] = v
  end

  if not local_config then
    goto continue
  end

  for k, v in pairs(local_config) do
    config[k] = v
  end

  ::continue::
  return config
end

return resolve_config()
