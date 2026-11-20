-- Explains the selected lines with a throwaway headless Claude session.
-- The `rundown` skill (~/.claude/skills/rundown) defines what Claude reads and the output shape.

local claude_session = require("claude_session")

local DEFAULT_MODEL = "sonnet"
-- Above this the file is not sent with the prompt and Claude reads it with its own tools.
local MAX_INLINE_FILE_LINES = 2000
local MAX_CONSUMER_LINES = 150
-- Treesitter node types that define something callers refer to by name.
local DEFINITION_TYPE_PATTERNS = { "function", "method", "class" }
-- Globs for test code, in the form `rg --glob` takes.
local TEST_GLOBS = {
  "**/tests/**",
  "**/test/**",
  "**/__tests__/**",
  "**/test_*",
  "**/*_test.*",
  "**/*.test.*",
  "**/*.spec.*",
  "**/conftest.py",
}

---Builds the prompt that invokes the `rundown` skill on a line range.
---@param file string absolute path
---@param start_line integer 1-based, inclusive
---@param end_line integer 1-based, inclusive
---@return string
local function build_prompt(file, start_line, end_line)
  return string.format("/rundown %s:%d-%d", file, start_line, end_line)
end

---Returns whether a treesitter node type defines something callers refer to by name.
---@param node_type string
---@return boolean
local function is_definition_type(node_type)
  for _, pattern in ipairs(DEFINITION_TYPE_PATTERNS) do
    if node_type:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

---Picks the name to search for consumers of, from the names of the definitions
---that enclose the selection, innermost first. Dunder names such as `__init__`
---are skipped because their callers do not mention them, so the class is used instead.
---@param enclosing_names string[] may be dotted, such as `M.run`
---@return string|nil
local function consumer_symbol(enclosing_names)
  for _, name in ipairs(enclosing_names) do
    local identifier = name:match("[%w_]+$")
    if identifier and #identifier >= 3 and not identifier:match("^__") then
      return identifier
    end
  end
  return nil
end

---Returns whether a path is test code, by the same conventions as `TEST_GLOBS`.
---@param path string
---@return boolean
local function is_test_path(path)
  local name = vim.fs.basename(path)
  if name:match("^test_") or name:match("_test%.") or name:match("%.test%.") or name:match("%.spec%.") then
    return true
  end
  if name == "conftest.py" then
    return true
  end
  for _, directory in ipairs({ "tests", "test", "__tests__" }) do
    if path:find("/" .. directory .. "/", 1, true) then
      return true
    end
  end
  return false
end

---Builds the argv that finds uses of `symbol` in the current directory, with 2 lines of context.
---@param symbol string
---@param include_tests boolean false leaves out test code, which says how the
---  symbol is tested rather than what relies on it
---@return string[]
local function consumer_search_command(symbol, include_tests)
  local command = {
    "rg",
    "--line-number",
    "--no-heading",
    "--fixed-strings",
    "--word-regexp",
    "--context",
    "2",
    "--max-count",
    "5",
    "--max-columns",
    "200",
  }
  if not include_tests then
    for _, glob in ipairs(TEST_GLOBS) do
      vim.list_extend(command, { "--glob", "!" .. glob })
    end
  end
  return vim.list_extend(command, { "--", symbol, "." })
end

---Builds the context sent on stdin so that Claude can answer without reading the
---file or searching for consumers itself. The `rundown` skill documents both blocks.
---@param file string absolute path
---@param file_lines string[]|nil the whole file, or nil to leave it for Claude to read
---@param symbol string|nil the name that was searched for
---@param search_output string|nil output of `consumer_search_command`
---@return string empty when there is nothing to send
local function build_context(file, file_lines, symbol, search_output)
  local parts = {}
  if file_lines then
    local numbered = {}
    for number, line in ipairs(file_lines) do
      numbered[number] = number .. "\t" .. line
    end
    table.insert(parts, string.format('<file path="%s">\n%s\n</file>', file, table.concat(numbered, "\n")))
  end
  if symbol and search_output then
    local hits = vim.split(vim.trim(search_output), "\n")
    local truncated = #hits > MAX_CONSUMER_LINES
    local shown = table.concat(vim.list_slice(hits, 1, MAX_CONSUMER_LINES), "\n")
    table.insert(
      parts,
      string.format('<consumers symbol="%s" truncated="%s">\n%s\n</consumers>', symbol, tostring(truncated), shown)
    )
  end
  return table.concat(parts, "\n\n")
end

---Builds the argv for a headless, read-only Claude session.
---The session is saved under `session_id` so that the reply window can resume it as a chat.
---@param prompt string
---@param model string
---@param session_id string UUID
---@return string[]
local function build_command(prompt, model, session_id)
  return {
    "claude",
    "-p",
    prompt,
    "--model",
    model,
    "--tools",
    "Read,Grep,Glob",
    "--allowedTools",
    "Read,Grep,Glob",
    "--strict-mcp-config",
    "--session-id",
    session_id,
  }
end

---Returns the names of the definitions that enclose a line, innermost first.
---Empty when the buffer has no treesitter parser.
---@param bufnr integer
---@param line integer 1-based
---@return string[]
local function enclosing_definition_names(bufnr, line)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, nil, { error = false })
  if not ok or not parser then
    return {}
  end
  parser:parse()
  local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
  local column = #(text:match("^%s*") or "")
  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { line - 1, column } })
  local names = {}
  while node do
    local name_node = node:field("name")[1]
    if name_node and is_definition_type(node:type()) then
      table.insert(names, vim.treesitter.get_node_text(name_node, bufnr))
    end
    node = node:parent()
  end
  return names
end

---Runs the rundown on a line range of the current buffer and shows the result.
---@param start_line integer 1-based, inclusive
---@param end_line integer 1-based, inclusive
local function run(start_line, end_line)
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" or vim.bo.buftype ~= "" then
    vim.notify("rundown: this buffer is not a file", vim.log.levels.WARN)
    return
  end

  vim.cmd("silent update") -- Claude reads the file from disk, so line numbers must match
  local session_id = claude_session.new_session_id()
  local cwd = vim.fs.root(0, ".git") or vim.fs.dirname(file)
  local command =
    build_command(build_prompt(file, start_line, end_line), vim.g.rundown_model or DEFAULT_MODEL, session_id)
  local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local file_lines = #buffer_lines <= MAX_INLINE_FILE_LINES and buffer_lines or nil
  local symbol = consumer_symbol(enclosing_definition_names(0, start_line))

  ---@param search_output string|nil
  local function ask_claude(search_output)
    vim.system(
      command,
      { cwd = cwd, text = true, stdin = build_context(file, file_lines, symbol, search_output) },
      vim.schedule_wrap(function(result)
        if result.code ~= 0 then
          local message = vim.trim((result.stderr or "") .. (result.stdout or ""))
          vim.notify("rundown: claude failed\n" .. message, vim.log.levels.ERROR)
          return
        end
        claude_session.show_float(claude_session.output_lines(result.stdout or ""), {
          title = "rundown",
          session_id = session_id,
          cwd = cwd,
          focus = true,
          placement = "cursor",
        })
      end)
    )
  end

  vim.notify(string.format("rundown: reading lines %d-%d", start_line, end_line))
  if not symbol or vim.fn.executable("rg") ~= 1 then
    ask_claude(nil)
    return
  end
  vim.system(
    consumer_search_command(symbol, is_test_path(file)),
    { cwd = cwd, text = true },
    vim.schedule_wrap(function(result)
      -- rg exits 1 when nothing matches, which is a result worth sending; 2 is an error
      ask_claude(result.code <= 1 and (result.stdout or "") or nil)
    end)
  )
end

return {
  build_prompt = build_prompt,
  enclosing_definition_names = enclosing_definition_names,
  consumer_symbol = consumer_symbol,
  is_test_path = is_test_path,
  consumer_search_command = consumer_search_command,
  build_context = build_context,
  build_command = build_command,
  run = run,
}
