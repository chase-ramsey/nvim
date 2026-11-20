-- Shared parts of the features that run a throwaway headless Claude session and
-- show its reply in a floating window: the window itself, and continuing the
-- session as an interactive chat. Used by lua/rundown.lua and lua/claude_task.lua.

local MAX_WIDTH = 90
local FOOTER = " c: chat about this   q: close "

---Builds the argv that resumes a saved session interactively, in a new window
---beside the current one (lemonaid picks tmux, WezTerm or cmux).
---The resumed session has Claude's normal tools and permission mode.
---@param session_id string UUID
---@return string[]
local function build_chat_command(session_id)
  return { "lemonaid", "lemon", "start", "--harness", "claude", "--json", "--", "--resume", session_id }
end

---Decodes the JSON that `lemonaid lemon start --json` prints.
---@param stdout string
---@return table result empty when the output is not a JSON object
local function decode_chat_result(stdout)
  local ok, decoded = pcall(vim.json.decode, stdout)
  return (ok and type(decoded) == "table") and decoded or {}
end

---Describes the outcome of `build_chat_command`.
---@param code integer exit code
---@param result table decoded output, see `decode_chat_result`
---@param raw_output string stdout and stderr, shown when `result` carries no error
---@return string message
---@return integer level a `vim.log.levels` value
local function chat_result_message(code, result, raw_output)
  local failure = type(result.error) == "string" and result.error or nil
  if code ~= 0 or failure then
    return "claude: could not start chat\n" .. (failure or vim.trim(raw_output)), vim.log.levels.ERROR
  end
  return "claude: chat started in " .. (result.where or "a new window"), vim.log.levels.INFO
end

---Builds the argv that switches to the chat's window. lemonaid starts it unfocused.
---@param result table decoded output, see `decode_chat_result`
---@return string[]|nil nil when the chat is not in a tmux window
local function focus_command(result)
  if result.front_end == "tmux" and type(result.window_id) == "string" then
    return { "tmux", "select-window", "-t", result.window_id }
  end
  return nil
end

---Splits Claude's output into lines without leading or trailing blank lines.
---@param output string
---@return string[]
local function output_lines(output)
  return vim.split(vim.trim(output), "\n")
end

---Computes a floating window that fits `lines`.
---@param lines string[]
---@param editor_width integer
---@param editor_height integer
---@param title string
---@param placement "cursor"|"corner" just below the cursor, or the top-right corner of the editor
---@return table config for `nvim_open_win`
local function float_config(lines, editor_width, editor_height, title, placement)
  local width = math.max(20, math.min(MAX_WIDTH, editor_width - 4))
  local height = 0
  for _, line in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  local config = {
    width = width,
    height = math.max(1, math.min(height, editor_height - 6)),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    footer = FOOTER,
    footer_pos = "right",
  }
  if placement == "corner" then
    config.relative = "editor"
    config.anchor = "NE"
    config.row = 1
    config.col = editor_width
  else
    config.relative = "cursor"
    config.row = 1
    config.col = 0
  end
  return config
end

---@return string a new lowercase UUID, the form `claude --session-id` takes
local function new_session_id()
  return vim.trim(vim.fn.system({ "uuidgen" })):lower()
end

---Resumes a saved session interactively so the conversation can continue.
---@param session_id string
---@param cwd string directory the session ran in; Claude looks up sessions by directory
local function start_chat(session_id, cwd)
  vim.notify("claude: starting chat")
  vim.system(
    build_chat_command(session_id),
    { cwd = cwd, text = true },
    vim.schedule_wrap(function(result)
      local chat_result = decode_chat_result(result.stdout or "")
      vim.notify(chat_result_message(result.code, chat_result, (result.stderr or "") .. (result.stdout or "")))
      local focus = result.code == 0 and focus_command(chat_result) or nil
      if focus then
        vim.system(focus)
      end
    end)
  )
end

---@class ClaudeFloatOptions
---@field title string
---@field session_id string the session that `c` resumes
---@field cwd string directory the session ran in
---@field focus boolean false leaves the cursor where it is, for a reply that arrives later
---@field placement "cursor"|"corner"

---Shows Claude's reply in a floating window. `q` and `<Esc>` close it, `c`
---closes it and continues the session as an interactive chat.
---@param lines string[]
---@param options ClaudeFloatOptions
---@return integer window
local function show_float(lines, options)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  local config = float_config(lines, vim.o.columns, vim.o.lines, options.title, options.placement)
  local win = vim.api.nvim_open_win(buf, options.focus, config)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, "<cmd>close<CR>", { buffer = buf, nowait = true, silent = true })
  end
  vim.keymap.set("n", "c", function()
    vim.cmd("close")
    start_chat(options.session_id, options.cwd)
  end, { buffer = buf, nowait = true, silent = true })
  return win
end

return {
  build_chat_command = build_chat_command,
  decode_chat_result = decode_chat_result,
  chat_result_message = chat_result_message,
  focus_command = focus_command,
  output_lines = output_lines,
  float_config = float_config,
  new_session_id = new_session_id,
  start_chat = start_chat,
  show_float = show_float,
}
