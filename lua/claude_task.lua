-- Hands an instruction to a throwaway headless Claude session that carries it
-- out in auto permission mode: it may edit files and run commands unattended.
-- The reply opens in a floating window; see lua/claude_session.lua for its keys.

local claude_session = require("claude_session")

local REPLY_RULES = table.concat({
  "This is a headless run started from the user's editor. Nobody can answer questions during it,",
  "so when something is ambiguous, pick the most likely meaning and state the assumption.",
  "Your final message is shown in a small floating window. Make it a few short lines:",
  "what you did and anything left undone or blocked. No headings. Do not list changed files:",
  "the editor appends that list from git. A <diagnostics> block, when present, holds what the",
  "editor's language tools report on the selected lines, as `line: severity (source): message`.",
}, " ")
local MAX_ACTIVITY_WIDTH = 60
local MAX_DENIAL_WIDTH = 80
local MAX_DIAGNOSTICS = 50
local MAX_CHANGED_FILES = 20
-- Limits on an unattended task; `vim.g.claude_task_max_usd` and
-- `vim.g.claude_task_timeout_minutes` override them.
local DEFAULT_MAX_USD = 5
local DEFAULT_TIMEOUT_MINUTES = 30
local SEVERITY_NAMES = { "error", "warning", "info", "hint" }
local INPUT_WIDTH = 80
local INPUT_HEIGHT = 8
-- The input fields worth showing for a tool call, in order of preference.
local ACTIVITY_FIELDS = { "file_path", "command", "pattern", "description", "prompt", "url", "query" }

---@class ClaudeTaskDiagnostic
---@field line integer 1-based
---@field severity integer 1 (error) to 4 (hint), as in `vim.diagnostic.severity`
---@field source string|nil the tool that reported it, such as `pyright`
---@field message string

---@class ClaudeTaskContext
---@field file string|nil absolute path of the buffer the task was started from
---@field start_line integer 1-based, inclusive
---@field end_line integer 1-based, inclusive
---@field selected_lines string[] the text of that range
---@field diagnostics ClaudeTaskDiagnostic[] what the editor reports on that range

---Collapses `text` onto one line.
---@param text string
---@return string
local function one_line(text)
  return vim.trim((text:gsub("%s+", " ")))
end

---Keeps the diagnostics on the given lines, most severe first, then by line.
---@param diagnostics ClaudeTaskDiagnostic[]
---@param start_line integer 1-based, inclusive
---@param end_line integer 1-based, inclusive
---@return ClaudeTaskDiagnostic[]
local function diagnostics_in_range(diagnostics, start_line, end_line)
  local kept = {}
  for _, diagnostic in ipairs(diagnostics) do
    if diagnostic.line >= start_line and diagnostic.line <= end_line then
      table.insert(kept, diagnostic)
    end
  end
  table.sort(kept, function(left, right)
    if left.severity ~= right.severity then
      return left.severity < right.severity
    end
    return left.line < right.line
  end)
  return kept
end

---Formats diagnostics one per line, such as `12: error (pyright): "x" is not defined`.
---@param diagnostics ClaudeTaskDiagnostic[]
---@return string[]
local function diagnostic_lines(diagnostics)
  local lines = {}
  for index, diagnostic in ipairs(diagnostics) do
    if index > MAX_DIAGNOSTICS then
      table.insert(lines, string.format("(%d more not shown)", #diagnostics - MAX_DIAGNOSTICS))
      break
    end
    local severity = SEVERITY_NAMES[diagnostic.severity] or "error"
    local source = diagnostic.source and (" (" .. diagnostic.source .. ")") or ""
    table.insert(lines, string.format("%d: %s%s: %s", diagnostic.line, severity, source, one_line(diagnostic.message)))
  end
  return lines
end

---Builds the text sent to Claude on stdin: the instruction, the lines the cursor
---or selection was on, and what the editor's diagnostics say about those lines.
---Claude reads anything else it needs itself.
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
  local parts = {
    instruction,
    string.format(
      '<context file="%s" lines="%d-%d">\n%s\n</context>',
      context.file,
      context.start_line,
      context.end_line,
      table.concat(numbered, "\n")
    ),
  }
  if #context.diagnostics > 0 then
    local lines = table.concat(diagnostic_lines(context.diagnostics), "\n")
    table.insert(parts, "<diagnostics>\n" .. lines .. "\n</diagnostics>")
  end
  return table.concat(parts, "\n\n")
end

---Builds the argv for a headless Claude session in auto permission mode that
---reports its progress as one JSON event per line. The session gets no MCP
---servers, so an unattended run cannot reach the account's connectors.
---@param model string|nil nil uses the model Claude is configured with
---@param session_id string UUID, so the reply window can resume the session as a chat
---@param max_usd number the session stops once it has spent this much
---@return string[]
local function build_task_command(model, session_id, max_usd)
  local command = {
    "claude",
    "-p",
    "--permission-mode",
    "auto",
    "--strict-mcp-config",
    "--max-budget-usd",
    tostring(max_usd),
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
    local errors = type(result_event.errors) == "table" and result_event.errors or {}
    local reason = #errors > 0 and table.concat(errors, "; ") or tostring(result_event.subtype or "unknown")
    reply = "(Claude stopped without a reply: " .. reason .. ")"
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

---Lists the files a task changed, from git's view before and after it ran.
---@param changed_tracked string output of `git diff --name-only` against the tree as it was before the task
---@param untracked_before string output of `git ls-files --others --exclude-standard` before the task
---@param untracked_after string the same, after the task
---@return string[] sorted paths relative to the repository root
local function changed_files(changed_tracked, untracked_before, untracked_after)
  local existed = {}
  for _, path in ipairs(vim.split(untracked_before, "\n", { trimempty = true })) do
    existed[path] = true
  end
  local changed = {}
  for _, path in ipairs(vim.split(changed_tracked, "\n", { trimempty = true })) do
    changed[path] = true
  end
  for _, path in ipairs(vim.split(untracked_after, "\n", { trimempty = true })) do
    if not existed[path] then
      changed[path] = true
    end
  end
  local paths = vim.tbl_keys(changed)
  table.sort(paths)
  return paths
end

---Appends git's account of what a task changed to its reply, so the list does
---not depend on what Claude says it did.
---@param lines string[] the reply
---@param files string[]|nil from `changed_files`; nil when the directory is not a git repository
---@return string[]
local function with_changed_files(lines, files)
  local result = vim.list_extend({}, lines)
  if not files then
    return result
  end
  if #files == 0 then
    return vim.list_extend(result, { "", "No files changed (git)." })
  end
  vim.list_extend(result, { "", "Changed files (git):" })
  for index, path in ipairs(files) do
    if index > MAX_CHANGED_FILES then
      table.insert(result, string.format("- and %d more", #files - MAX_CHANGED_FILES))
      break
    end
    table.insert(result, "- " .. path)
  end
  return result
end

---Builds the reply shown for a task that was stopped at its time limit.
---@param minutes number
---@return string[]
local function timeout_lines(minutes)
  return {
    string.format("Stopped: the task was still running after %s minutes.", tostring(minutes)),
    "Edits it had already made are on disk. Press c to continue it as a chat.",
  }
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
---@field timed_out boolean

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

---@param command string[]
---@param cwd string
---@return string|nil stdout nil when the command failed
local function git_output(command, cwd)
  local result = vim.system(command, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return result.stdout or ""
end

---@class ClaudeTaskSnapshot
---@field base string a commit holding the tracked files as they were
---@field untracked string the untracked files as they were, one per line

---Records the state of the working tree so that `files_changed_since` can say
---what a task changed, including in files that were already modified.
---`git stash create` writes a commit of the tracked changes without touching
---the working tree, the index or the stash list.
---@param cwd string
---@return ClaudeTaskSnapshot|nil nil outside a git repository, or in one with no commits
local function snapshot_worktree(cwd)
  if vim.fn.executable("git") ~= 1 then
    return nil
  end
  local stash = git_output({ "git", "stash", "create" }, cwd)
  local base = stash and vim.trim(stash) or ""
  if base == "" then
    base = vim.trim(git_output({ "git", "rev-parse", "--verify", "HEAD" }, cwd) or "")
  end
  local untracked = git_output({ "git", "ls-files", "--others", "--exclude-standard" }, cwd)
  if base == "" or not untracked then
    return nil
  end
  return { base = base, untracked = untracked }
end

---@param snapshot ClaudeTaskSnapshot|nil
---@param cwd string
---@return string[]|nil nil when there is no snapshot to compare with
local function files_changed_since(snapshot, cwd)
  if not snapshot then
    return nil
  end
  local changed_tracked = git_output({ "git", "diff", "--name-only", snapshot.base }, cwd)
  local untracked = git_output({ "git", "ls-files", "--others", "--exclude-standard" }, cwd)
  if not changed_tracked or not untracked then
    return nil
  end
  return changed_files(changed_tracked, snapshot.untracked, untracked)
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
  local task = { started = os.time(), activity = "starting", cancelled = false, timed_out = false }
  local max_usd = vim.g.claude_task_max_usd or DEFAULT_MAX_USD
  local timeout_minutes = vim.g.claude_task_timeout_minutes or DEFAULT_TIMEOUT_MINUTES
  local snapshot = snapshot_worktree(cwd)

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

  -- Not `vim.system`'s own timeout: Claude exits with its own code on SIGTERM,
  -- so the exit code cannot tell a time limit from any other failure.
  local time_limit = assert(vim.uv.new_timer())
  time_limit:start(math.floor(timeout_minutes * 60 * 1000), 0, function()
    task.timed_out = true
    task.process:kill("sigterm")
  end)

  task.process = vim.system(
    build_task_command(vim.g.claude_task_model, session_id, max_usd),
    {
      cwd = cwd,
      text = true,
      stdin = build_task_input(instruction, context),
      stdout = on_stdout,
    },
    vim.schedule_wrap(function(result)
      time_limit:stop()
      time_limit:close()
      read_line(pending_output) -- a last line with no newline after it
      forget_task(task)
      local timed_out = task.timed_out and not result_event
      if task.cancelled then
        vim.notify("claude: task cancelled")
      elseif not result_event and not timed_out then
        vim.notify(failure_message(result.code, result.signal, result.stderr or ""), vim.log.levels.ERROR)
      else
        local reply = result_event and result_lines(result_event) or timeout_lines(timeout_minutes)
        claude_session.show_reply(with_changed_files(reply, files_changed_since(snapshot, cwd)), {
          title = "claude task",
          session_id = session_id,
          cwd = cwd,
          focus = false,
          placement = "corner",
        })
        local outcome = timed_out and "stopped at its time limit" or "finished"
        vim.notify("claude: task " .. outcome .. ", :ClaudeReply to open the reply")
      end
      -- The task may have edited files that are open. Last, and guarded, because
      -- it raises in some states (the command-line window) and must not cost the reply.
      pcall(vim.cmd, "checktime")
    end)
  )
  table.insert(running_tasks, task)
  render_indicator()
end

---@param bufnr integer
---@return ClaudeTaskDiagnostic[]
local function buffer_diagnostics(bufnr)
  local diagnostics = {}
  for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
    table.insert(diagnostics, {
      line = diagnostic.lnum + 1,
      severity = diagnostic.severity,
      source = diagnostic.source,
      message = diagnostic.message,
    })
  end
  return diagnostics
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
    diagnostics = diagnostics_in_range(buffer_diagnostics(0), start_line, end_line),
  }
  local cwd = (is_file and (vim.fs.root(0, ".git") or vim.fs.dirname(file))) or vim.fn.getcwd()
  local title = is_file and string.format("%s:%d-%d", vim.fs.basename(file), start_line, end_line) or "no file"
  if is_file and #context.diagnostics > 0 then
    local noun = #context.diagnostics == 1 and "diagnostic" or "diagnostics"
    title = string.format("%s · %d %s", title, #context.diagnostics, noun)
  end

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
  diagnostics_in_range = diagnostics_in_range,
  diagnostic_lines = diagnostic_lines,
  build_task_input = build_task_input,
  build_task_command = build_task_command,
  split_complete_lines = split_complete_lines,
  one_line = one_line,
  decode_event = decode_event,
  failure_message = failure_message,
  changed_files = changed_files,
  with_changed_files = with_changed_files,
  timeout_lines = timeout_lines,
  progress_line = progress_line,
  result_lines = result_lines,
  format_elapsed = format_elapsed,
  indicator_line = indicator_line,
  run = run,
  open_input = open_input,
  cancel = cancel,
}
