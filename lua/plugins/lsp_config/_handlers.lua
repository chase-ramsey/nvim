local CONFIG = require("config")
local utils = require("utils")


local function filter_cat_type_errors(err, result, ctx, config)
  local filtered_diagnostics = {}
  for _, diag in ipairs(result.diagnostics) do
    if diag.code and string.match(diag.code, "reportCallIssue") then
      if string.match(diag.message, "No parameter named") or string.match(diag.message, "Expected 0") then
        -- TODO: it would be great to not blanket ignore these cases,
        --       but currently, it appears it would be too difficult
        --       to be more targeted.
        goto continue
      end
    end

    if string.match(diag.message, 'attribute "u?n?struc"') then
      goto continue
    end

    table.insert(filtered_diagnostics, diag)
    ::continue::
  end

  result.diagnostics = filtered_diagnostics

  return err, result, ctx, config
end


local function compose_lsp_diagnostics_handlers()
  local handlers = {}
  -- NOTE: all of the handlers must accept and return arguments
  --       matching the signature of vim.lsp.diagnostic.on_publish_diagnostics
  if CONFIG.lsp_config.python.filter_cat_type_errors then
    table.insert(handlers, filter_cat_type_errors)
  end

  -- NOTE: vim.lsp.diagnostic.on_publish_diagnostics _does not_ return values
  table.insert(handlers, vim.lsp.diagnostic.on_publish_diagnostics)
  return utils.compose(handlers)
end

return {
  compose_lsp_diagnostics_handlers = compose_lsp_diagnostics_handlers
}
