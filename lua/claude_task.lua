-- Hands an instruction to a throwaway headless Claude session that carries it
-- out in auto permission mode: it may edit files and run commands unattended.
-- The reply opens in a floating window; see lua/claude_session.lua for its keys.

local claude_session = require("claude_session")

local REPLY_RULES = table.concat({
  "This is a headless run started from the user's editor. Nobody can answer questions during it,",
  "so when something is ambiguous, pick the most likely meaning and state the assumption.",
  "Your final message is shown in a small floating window. Make it a few short lines:",
  "what you did, which files changed, and anything left undone or blocked. No headings.",
}, " ")
local MAX_ACTIVITY_WIDTH = 60
local MAX_DENIAL_WIDTH = 80
local INPUT_WIDTH = 80
local INPUT_HEIGHT = 8
-- The input fields worth showing for a tool call, in order of preference.
local ACTIVITY_FIELDS = { "file_path", "command", "pattern", "description", "prompt", "url", "query" }

---@class ClaudeTaskContext
---@field file string|nil absolute path of the buffer the task was started from
---@field start_line integer 1-based, inclusive
---@field end_line integer 1-based, inclusive
---@field selected_lines string[] the text of that range

---Builds the text sent to Claude on stdin: the instruction, then the lines the
---cursor or selection was on. Claude reads anything else it needs itself.
---@param instruction string
---@param context ClaudeTaskContext
---@return string
local function build_task_input(instruction, context)
  if not context.file then
    return instruction
  end
  local numbered = {}
  for offset, line in ipairs(context.selected_lines) do
    table.insert(numbered, (context.start_line + offset - 1) .. "\t" .. line)
  end
  return string.format(
    '%s\n\n<context file="%s" lines="%d-%d">\n%s\n</context>',
    instruction,
    context.file,
    context.start_line,
    context.end_line,
    table.concat(numbered, "\n")
  )
end

---Builds the argv for a headless Claude session in auto permission mode that
---reports its progress as one JSON event per line.
---@param model string|nil nil uses the model Claude is configured with
---@param session_id string UUID, so the reply window can resume the session as a chat
---@return string[]
local function build_task_command(model, session_id)
  local command = {
    "claude",
    "-p",
    "--permission-mode",
    "auto",
    "--session-id",
    session_id,
    "--output-format",
    "stream-json",
    "--verbose",
    "--append-system-prompt",
    REPLY_RULES,
  }
  if model then
    vim.list_extend(command, { "--model", model })
  end
  return command
end

---Splits streamed output into complete lines, keeping an unfinished last line for the next chunk.
---@param pending string text left over from earlier chunks
---@param chunk string
---@return string[] lines
---@return string remainder
local function split_complete_lines(pending, chunk)
  local lines = vim.split(pending .. chunk, "\n", { plain = true })
  local remainder = table.remove(lines)
  return lines, remainder
end

---Collapses `text` onto one line.
---@param text string
---@return string
local function one_line(text)
  return vim.trim((text:gsub("%s+", " ")))
end

---Describes what Claude is doing, from one stream-json event.
---@param event table
---@param cwd string removed from the front of paths, to keep the line short
---@return string|nil nil for an event that does not change what Claude is doing
local function progress_line(event, cwd)
  if event.type ~= "assistant" or type(event.message) ~= "table" or type(event.message.content) ~= "table" then
    return nil
  end
  local activity = nil
  for _, block in ipairs(event.message.content) do
    if block.type == "tool_use" then
      local detail = ""
      for _, field in ipairs(ACTIVITY_FIELDS) do
        local value = type(block.input) == "table" and block.input[field] or nil
        if type(value) == "string" and value ~= "" then
          detail = value
          break
        end
      end
      if detail:sub(1, #cwd + 1) == cwd .. "/" then
        detail = detail:sub(#cwd + 2)
      end
      activity = one_line(block.name .. " " .. detail)
    elseif block.type == "text" then
      activity = "writing"
    elseif block.type == "thinking" and not activity then
      activity = "thinking"
    end
  end
  return activity
end

---Builds the lines of the reply window from the final stream-json event.
---Actions that auto mode refused are listed, because the reply may not mention them.
---Not callable from a `vim.system` output callback (see `claude_session.truncate`).
---@param result_event table the event with `type == "result"`
---@return string[]
local function result_lines(result_event)
  local reply = type(result_event.result) == "string" and vim.trim(result_event.result) or ""
  if reply == "" then
    reply = "(Claude finished without a reply: " .. tostring(result_event.subtype or "unknown") .. ")"
  end
  local lines = claude_session.output_lines(reply)
  local denials = type(result_event.permission_denials) == "table" and result_event.permission_denials or {}
  if #denials > 0 then
    vim.list_extend(lines, { "", "Blocked by auto mode:" })
    for _, denial in ipairs(denials) do
      local input = type(denial.tool_input) == "table" and denial.tool_input or {}
      local detail = input.command or input.file_path or ""
      local action = one_line(tostring(denial.tool_name) .. " " .. tostring(detail))
      table.insert(lines, "- " .. claude_session.truncate(action, MAX_DENIAL_WIDTH))
    end
  end
  return lines
end

---Decodes one line of stream-json output.
---@param line string
---@return table|nil event nil for a line that is not a JSON object
local function decode_event(line)
  local ok, event = pcall(vim.json.decode, line)
  if ok and type(event) == "table" then
    return event
  end
  return nil
end

---Describes a task that ended without a reply.
---@param code integer exit code
---@param signal integer the signal that ended it, or 0
---@param stderr string
---@return string
local function failure_message(code, signal, stderr)
  local how = signal ~= 0 and ("killed by signal " .. signal) or ("exit " .. code)
  return vim.trim("claude: task failed (" .. how .. ")\n" .. vim.trim(stderr))
end

---@param seconds integer
---@return string such as `0:42`
local function format_elapsed(seconds)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

---@param elapsed_seconds integer
---@param activity string
---@return string
local function indicator_line(elapsed_seconds, activity)
  return string.format(" claude %s · %s ", format_elapsed(elapsed_seconds), activity)
end

-- Everything below reads or changes editor state.

---@class ClaudeRunningTask
---@field started integer seconds, from `os.time()`
---@field activity string
---@field process vim.SystemObj
---@field cancelled boolean

---@type ClaudeRunningTask[]
local running_tasks = {}
---@type integer|nil
local indicator_window = nil
---@type uv.uv_timer_t|nil
local indicator_timer = nil
local function close_indicator()
  if indicator_timer then
    indicator_timer:stop()
    indicator_timer:close()
    indicator_timer = nil
  end
  if indicator_window and vim.api.nvim_win_is_valid(indicator_window) then
    vim.api.nvim_win_close(indicator_window, true)
  end
  indicator_window = nil
end

---Draws one line per running task in the top-right corner, or removes the window when none run.
local function render_indicator()
  if #running_tasks == 0 then
    close_indicator()
    return
  end
  local lines = {}
  local width = 1
  for _, task in ipairs(running_tasks) do
    local activity = claude_session.truncate(task.activity, MAX_ACTIVITY_WIDTH)
    local line = indicator_line(os.time() - task.started, activity)
    table.insert(lines, line)
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  local config = {
    relative = "editor",
    anchor = "NE",
    row = 0,
    col = vim.o.columns,
    width = width,
    height = #lines,
    style = "minimal",
    focusable = false,
    zindex = 60,
  }
  if indicator_window and vim.api.nvim_win_is_valid(indicator_window) then
    vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(indicator_window), 0, -1, false, lines)
    vim.api.nvim_win_set_config(indicator_window, config)
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  config.noautocmd = true
  indicator_window = vim.api.nvim_open_win(buf, false, config)
  if not indicator_timer then
    indicator_timer = assert(vim.uv.new_timer())
    indicator_timer:start(1000, 1000, vim.schedule_wrap(render_indicator))
  end
end

---@param task ClaudeRunningTask
local function forget_task(task)
  for index, candidate in ipairs(running_tasks) do
    if candidate == task then
      table.remove(running_tasks, index)
      break
    end
  end
  render_indicator()
end

---Starts a headless Claude session on `instruction` and shows its reply when it ends.
---@param instruction string
---@param context ClaudeTaskContext
---@param cwd string
local function run(instruction, context, cwd)
  local session_id = claude_session.new_session_id()
  local pending_output = ""
  ---@type table|nil
  local result_event = nil
  ---@type ClaudeRunningTask
  local task = { started = os.time(), activity = "starting", cancelled = false }

  ---@param line string
  local function read_line(line)
    local event = decode_event(line)
    if not event then
      return
    end
    if event.type == "result" then
      result_event = event
    end
    task.activity = progress_line(event, cwd) or task.activity
  end

  ---@param _ string|nil error
  ---@param chunk string|nil nil at the end of the stream
  local function on_stdout(_, chunk)
    if not chunk then
      return
    end
    local lines
    lines, pending_output = split_complete_lines(pending_output, chunk)
    for _, line in ipairs(lines) do
      read_line(line)
    end
  end

  task.process = vim.system(
    build_task_command(vim.g.claude_task_model, session_id),
    { cwd = cwd, text = true, stdin = build_task_input(instruction, context), stdout = on_stdout },
    vim.schedule_wrap(function(result)
      read_line(pending_output) -- a last line with no newline after it
      forget_task(task)
      if task.cancelled then
        vim.notify("claude: task cancelled")
      elseif not result_event then
        vim.notify(failure_message(result.code, result.signal, result.stderr or ""), vim.log.levels.ERROR)
      else
        claude_session.show_reply(result_lines(result_event), {
          title = "claude task",
          session_id = session_id,
          cwd = cwd,
          focus = false,
          placement = "corner",
        })
        vim.notify("claude: task finished, :ClaudeReply to open the reply")
      end
      -- The task may have edited files that are open. Last, and guarded, because
      -- it raises in some states (the command-line window) and must not cost the reply.
      pcall(vim.cmd, "checktime")
    end)
  )
  table.insert(running_tasks, task)
  render_indicator()
end

---Opens a floating scratch buffer for the instruction. The lines `start_line`
---to `end_line` of the current buffer are sent with it as context.
---@param start_line integer 1-based, inclusive
---@param end_line integer 1-based, inclusive
local function open_input(start_line, end_line)
  if not claude_session.require_executables("claude task", { "claude" }) then
    return
  end
  local file = vim.api.nvim_buf_get_name(0)
  local is_file = file ~= "" and vim.bo.buftype == ""
  if is_file then
    vim.cmd("silent update") -- Claude reads and edits the file on disk
  end
  ---@type ClaudeTaskContext
  local context = {
    file = is_file and file or nil,
    start_line = start_line,
    end_line = end_line,
    selected_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false),
  }
  local cwd = (is_file and (vim.fs.root(0, ".git") or vim.fs.dirname(file))) or vim.fn.getcwd()
  local title = is_file and string.format("%s:%d-%d", vim.fs.basename(file), start_line, end_line) or "no file"

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  local width = math.max(20, math.min(INPUT_WIDTH, vim.o.columns - 4))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - INPUT_HEIGHT) / 3)),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = INPUT_HEIGHT,
    style = "minimal",
    border = "rounded",
    title = " claude task · " .. title .. " ",
    footer = " <C-s>: send   <Esc> then q: cancel ",
    footer_pos = "right",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local function submit()
    local instruction = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
    vim.cmd("stopinsert")
    vim.api.nvim_win_close(win, true)
    if instruction == "" then
      vim.notify("claude: no instruction, nothing sent")
      return
    end
    run(instruction, context, cwd)
  end

  vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<CR>", submit, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, nowait = true, silent = true })
  vim.cmd("startinsert")
end

---Stops every running task. Edits a task already made stay on disk.
---@param quiet boolean|nil true skips the warning when nothing is running
local function cancel(quiet)
  if #running_tasks == 0 and not quiet then
    vim.notify("claude: no task is running", vim.log.levels.WARN)
    return
  end
  for _, task in ipairs(running_tasks) do
    task.cancelled = true
    task.process:kill("sigterm")
  end
end

-- A task's reply can only be shown in the editor that started it, so tasks do
-- not outlive it: left running they would finish, or fail, with nobody told.
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("claude_task_stop_on_exit", { clear = true }),
  callback = function()
    cancel(true)
  end,
  desc = "Stop running Claude tasks when neovim exits",
})

return {
  build_task_input = build_task_input,
  build_task_command = build_task_command,
  split_complete_lines = split_complete_lines,
  one_line = one_line,
  decode_event = decode_event,
  failure_message = failure_message,
  progress_line = progress_line,
  result_lines = result_lines,
  format_elapsed = format_elapsed,
  indicator_line = indicator_line,
  run = run,
  open_input = open_input,
  cancel = cancel,
}
