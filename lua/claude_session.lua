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

---Formats 16 random bytes as a version 4 UUID, the form `claude --session-id` takes.
---@param bytes string 16 bytes
---@return string
local function format_uuid(bytes)
  local hex = {}
  for index = 1, 16 do
    local byte = bytes:byte(index)
    if index == 7 then
      byte = byte % 16 + 0x40 -- version 4
    elseif index == 9 then
      byte = byte % 64 + 0x80 -- RFC 4122 variant
    end
    hex[index] = string.format("%02x", byte)
  end
  local joined = table.concat(hex)
  return string.format(
    "%s-%s-%s-%s-%s",
    joined:sub(1, 8),
    joined:sub(9, 12),
    joined:sub(13, 16),
    joined:sub(17, 20),
    joined:sub(21, 32)
  )
end

---Shortens `text` to at most `width` characters, never splitting a character.
---Not callable from a `vim.system` output callback, because it uses `vim.fn`.
---@param text string
---@param width integer
---@return string
local function truncate(text, width)
  if vim.fn.strchars(text) <= width then
    return text
  end
  return vim.fn.strcharpart(text, 0, width - 1) .. "…"
end

---Returns the executables in `names` that are not on PATH.
---@param names string[]
---@param is_executable fun(name: string): boolean
---@return string[]
local function missing_executables(names, is_executable)
  local missing = {}
  for _, name in ipairs(names) do
    if not is_executable(name) then
      table.insert(missing, name)
    end
  end
  return missing
end

---Picks which stored reply to open.
---@param reply_count integer
---@param nth integer 1 is the newest reply, 2 the one before it
---@return integer|nil index into the list of replies, oldest first; nil when there is no such reply
local function reply_index(reply_count, nth)
  local index = reply_count - nth + 1
  if nth < 1 or index < 1 then
    return nil
  end
  return index
end

-- Everything below reads or changes editor state.

---@return string a new UUID for `claude --session-id`
local function new_session_id()
  return format_uuid(assert(vim.uv.random(16)))
end

---Reports executables a feature needs that are not on PATH.
---@param feature string the prefix of the message, such as `rundown`
---@param names string[]
---@return boolean ok false when something is missing and the caller should stop
local function require_executables(feature, names)
  local missing = missing_executables(names, function(name)
    return vim.fn.executable(name) == 1
  end)
  if #missing == 0 then
    return true
  end
  vim.notify(feature .. ": not on PATH: " .. table.concat(missing, ", "), vim.log.levels.ERROR)
  return false
end

---Resumes a saved session interactively so the conversation can continue.
---@param session_id string
---@param cwd string directory the session ran in; Claude looks up sessions by directory
local function start_chat(session_id, cwd)
  if not require_executables("claude", { "lemonaid" }) then
    return
  end
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

---@class ClaudeReply
---@field lines string[]
---@field title string
---@field session_id string the session that `c` resumes
---@field cwd string directory the session ran in
---@field window integer|nil the window showing it, when one is open

-- Replies are kept here, oldest first, so that one whose window was closed
-- (by `:only`, or by a newer reply) can be opened again.
local MAX_REPLIES = 20
---@type ClaudeReply[]
local replies = {}

---@param reply ClaudeReply
---@return boolean
local function is_open(reply)
  return reply.window ~= nil and vim.api.nvim_win_is_valid(reply.window)
end

---Opens a floating window on a stored reply. `q` and `<Esc>` close it, `c`
---closes it and continues the session as an interactive chat.
---@param reply ClaudeReply
---@param focus boolean false leaves the cursor where it is
---@param placement "cursor"|"corner"
local function open_reply(reply, focus, placement)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, reply.lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  local config = float_config(reply.lines, vim.o.columns, vim.o.lines, reply.title, placement)
  reply.window = vim.api.nvim_open_win(buf, focus, config)
  vim.wo[reply.window].wrap = true
  vim.wo[reply.window].linebreak = true
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, "<cmd>close<CR>", { buffer = buf, nowait = true, silent = true })
  end
  vim.keymap.set("n", "c", function()
    vim.cmd("close")
    start_chat(reply.session_id, reply.cwd)
  end, { buffer = buf, nowait = true, silent = true })
end

---@class ClaudeReplyOptions
---@field title string
---@field session_id string the session that `c` resumes
---@field cwd string directory the session ran in
---@field focus boolean false leaves the cursor where it is, for a reply that arrives while the user is busy
---@field placement "cursor"|"corner"

---Closes open reply windows. Replies open in the same corner, so a second
---window would cover the first.
---@param keep integer|nil a window to leave open
local function close_replies(keep)
  for _, reply in ipairs(replies) do
    if is_open(reply) and reply.window ~= keep then
      vim.api.nvim_win_close(reply.window, true)
    end
  end
end

---Returns whether the cursor is in a reply window.
---@return boolean
local function is_reading_reply()
  local current_window = vim.api.nvim_get_current_win()
  for _, reply in ipairs(replies) do
    if reply.window == current_window then
      return true
    end
  end
  return false
end

---Stores Claude's reply and shows it in a floating window. `open_stored_reply`
---brings back a reply whose window has been closed.
---@param lines string[]
---@param options ClaudeReplyOptions
---@return boolean shown false when a reply is being read, so the new one was stored without a window
local function show_reply(lines, options)
  ---@type ClaudeReply
  local reply = { lines = lines, title = options.title, session_id = options.session_id, cwd = options.cwd }
  -- Stored before any window changes, so a failure there cannot lose it.
  table.insert(replies, reply)
  while #replies > MAX_REPLIES do
    table.remove(replies, 1)
  end
  if is_reading_reply() then
    return false -- a window here would cover the reply being read
  end
  close_replies(nil)
  open_reply(reply, options.focus, options.placement)
  return true
end

---Moves the cursor into a stored reply, reopening its window if it was closed.
---@param nth integer 1 is the newest reply, 2 the one before it
local function open_stored_reply(nth)
  local index = reply_index(#replies, nth)
  if not index then
    local message = #replies == 0 and "claude: no replies yet" or ("claude: only " .. #replies .. " replies stored")
    vim.notify(message, vim.log.levels.WARN)
    return
  end
  local reply = replies[index]
  if is_open(reply) then
    vim.api.nvim_set_current_win(reply.window)
    return
  end
  close_replies(nil)
  open_reply(reply, true, "corner")
end

return {
  build_chat_command = build_chat_command,
  decode_chat_result = decode_chat_result,
  chat_result_message = chat_result_message,
  focus_command = focus_command,
  output_lines = output_lines,
  float_config = float_config,
  format_uuid = format_uuid,
  truncate = truncate,
  missing_executables = missing_executables,
  reply_index = reply_index,
  new_session_id = new_session_id,
  require_executables = require_executables,
  start_chat = start_chat,
  show_reply = show_reply,
  open_stored_reply = open_stored_reply,
}
