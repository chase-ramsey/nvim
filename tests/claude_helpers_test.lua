-- Tests for the pure helpers behind the Claude keymaps.
-- Run from the repository root: nvim -l tests/claude_helpers_test.lua

local root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(arg[0])))
package.path = root .. "/lua/?.lua;" .. package.path

local claude_session = require("claude_session")
local claude_task = require("claude_task")
local rundown = require("rundown")

local failures = 0

---@param name string
---@param actual any
---@param expected any
local function check(name, actual, expected)
  if not vim.deep_equal(actual, expected) then
    failures = failures + 1
    print(string.format("FAIL %s\n  expected %s\n  actual   %s", name, vim.inspect(expected), vim.inspect(actual)))
  end
end

-- rundown: which symbol to search for consumers of

check("a Python function is a definition", rundown.is_definition_type("function_definition"), true)
check("a Lua function is a definition", rundown.is_definition_type("function_declaration"), true)
check("a class is a definition", rundown.is_definition_type("class_definition"), true)
check("a Lua call is not a definition", rundown.is_definition_type("function_call"), false)
check("a method call is not a definition", rundown.is_definition_type("method_call"), false)
check("an argument is not a definition", rundown.is_definition_type("keyword_argument"), false)

check("dunder is skipped for the class", rundown.consumer_symbol({ "__init__", "Loader" }), "Loader")
check("dotted name gives its last part", rundown.consumer_symbol({ "M.run" }), "run")
check("short names are skipped", rundown.consumer_symbol({ "f" }), nil)
check("no names gives no symbol", rundown.consumer_symbol({}), nil)

check(
  "cursor inside a function names it, then what encloses it",
  rundown.selection_definition_names(
    { { { name = "save", start_line = 10 }, { name = "Store", start_line = 2 } } },
    12,
    12
  ),
  { "save", "Store" }
)
check(
  "a decorator selected with its method names the method, not the class",
  rundown.selection_definition_names({
    { { name = "Store", start_line = 2 } },
    { { name = "save", start_line = 10 }, { name = "Store", start_line = 2 } },
  }, 9, 12),
  { "save", "Store" }
)
check(
  "a comment selected above a top-level function names the function",
  rundown.selection_definition_names({ {}, { { name = "load", start_line = 5 } } }, 4, 8),
  { "load" }
)
check(
  "a selected class names the class, not its first method",
  rundown.selection_definition_names({
    { { name = "Store", start_line = 2 } },
    { { name = "save", start_line = 3 }, { name = "Store", start_line = 2 } },
  }, 2, 20),
  { "Store", "Store" }
)
check("no parser output gives no names", rundown.selection_definition_names({}, 1, 1), {})

check("normal mode in the starting window takes focus", rundown.should_focus_reply("n", true), true)
check("insert mode does not take focus", rundown.should_focus_reply("i", true), false)
check("another window does not take focus", rundown.should_focus_reply("n", false), false)

-- rundown: test files, the search command and the context sent to Claude

for path, expected in pairs({
  ["/a/tests/x.py"] = true,
  ["/a/src/test_x.py"] = true,
  ["/a/src/x_test.go"] = true,
  ["/a/x.spec.ts"] = true,
  ["/a/conftest.py"] = true,
  ["/a/src/latest.py"] = false,
  ["/a/src/contest/x.py"] = false,
  ["/a/src/testing.py"] = false,
}) do
  check("is_test_path " .. path, rundown.is_test_path(path), expected)
end

check(
  "tests are excluded by glob",
  vim.tbl_contains(rundown.consumer_search_command("run", false), "!**/tests/**"),
  true
)
check("tests are kept for test code", vim.tbl_contains(rundown.consumer_search_command("run", true), "--glob"), false)
check("the symbol follows --", vim.list_slice(rundown.consumer_search_command("run", true), 12), { "--", "run", "." })

check(
  "context has the numbered file and the consumers",
  rundown.build_context("/a.py", { "x = 1", "y" }, "foo", "a.py:1:foo()\n"),
  '<file path="/a.py">\n1\tx = 1\n2\ty\n</file>\n\n<consumers symbol="foo" truncated="false">\na.py:1:foo()\n</consumers>'
)
check("context is empty with nothing to send", rundown.build_context("/a.py", nil, nil, nil), "")
check("prompt names the range", rundown.build_prompt("/a.py", 3, 5), "/rundown /a.py:3-5")

-- claude_session

check(
  "format_uuid sets the version and variant",
  claude_session.format_uuid(string.rep("\255", 16)),
  "ffffffff-ffff-4fff-bfff-ffffffffffff"
)
check("format_uuid of zeros", claude_session.format_uuid(string.rep("\0", 16)), "00000000-0000-4000-8000-000000000000")

check("truncate leaves short text", claude_session.truncate("abc", 3), "abc")
check("truncate counts characters, not bytes", claude_session.truncate("ééééé", 4), "ééé…")

check(
  "missing_executables lists what is absent",
  claude_session.missing_executables({ "claude", "rg" }, function(name)
    return name == "rg"
  end),
  { "claude" }
)

check("newest reply", claude_session.reply_index(3, 1), 3)
check("the reply before it", claude_session.reply_index(3, 2), 2)
check("no such reply", claude_session.reply_index(3, 4), nil)
check("no replies", claude_session.reply_index(0, 1), nil)

check(
  "chat started",
  { claude_session.chat_result_message(0, { where = "tmux window x:8" }, "") },
  { "claude: chat started in tmux window x:8", vim.log.levels.INFO }
)
check(
  "chat error from lemonaid",
  { claude_session.chat_result_message(0, { error = "boom" }, "") },
  { "claude: could not start chat\nboom", vim.log.levels.ERROR }
)
check(
  "a null error is not a failure",
  { claude_session.chat_result_message(0, claude_session.decode_chat_result('{"error":null}'), "") },
  { "claude: chat started in a new window", vim.log.levels.INFO }
)
check("unparseable output decodes to empty", claude_session.decode_chat_result("nope"), {})
check(
  "tmux window is focused",
  claude_session.focus_command({ front_end = "tmux", window_id = "@9" }),
  { "tmux", "select-window", "-t", "@9" }
)
check("other front ends are not", claude_session.focus_command({ front_end = "wezterm" }), nil)

-- claude_task

check(
  "task input carries the numbered selection",
  claude_task.build_task_input("do it", { file = "/a.py", start_line = 3, end_line = 4, selected_lines = { "x", "y" } }),
  'do it\n\n<context file="/a.py" lines="3-4">\n3\tx\n4\ty\n</context>'
)
check(
  "task input without a file is the instruction",
  claude_task.build_task_input("do it", { start_line = 1, end_line = 1, selected_lines = {} }),
  "do it"
)
check(
  "model is passed when set",
  vim.list_slice(claude_task.build_task_command("opus", "ID"), 12),
  { "--model", "opus" }
)
check("model is left out by default", vim.tbl_contains(claude_task.build_task_command(nil, "ID"), "--model"), false)

check(
  "complete lines are split from the unfinished one",
  { claude_task.split_complete_lines('{"a"', ':1}\n{"b":2}\n{"c"') },
  { { '{"a":1}', '{"b":2}' }, '{"c"' }
)

---@param content any
---@return table
local function assistant(content)
  return { type = "assistant", message = { content = content } }
end

check(
  "tool call shows its path relative to the working directory",
  claude_task.progress_line(
    assistant({ { type = "tool_use", name = "Edit", input = { file_path = "/repo/a/b.py" } } }),
    "/repo"
  ),
  "Edit a/b.py"
)
check(
  "a command is put on one line",
  claude_task.progress_line(
    assistant({ { type = "tool_use", name = "Bash", input = { command = "a \\\n  b" } } }),
    "/repo"
  ),
  "Bash a \\ b"
)
check(
  "text means writing",
  claude_task.progress_line(assistant({ { type = "text", text = "hi" } }), "/repo"),
  "writing"
)
check("null content is ignored", claude_task.progress_line(assistant(vim.NIL), "/repo"), nil)
check("other events are ignored", claude_task.progress_line({ type = "user" }, "/repo"), nil)

check("a JSON object decodes", claude_task.decode_event('{"type":"result"}'), { type = "result" })
check("an empty line does not", claude_task.decode_event(""), nil)
check("a JSON scalar does not", claude_task.decode_event("3"), nil)

check("reply lines", claude_task.result_lines({ result = "done\n\nmore\n" }), { "done", "", "more" })
check(
  "refused actions are listed",
  claude_task.result_lines({
    result = "done",
    permission_denials = { { tool_name = "Bash", tool_input = { command = "rm -rf /" } } },
  }),
  { "done", "", "Blocked by auto mode:", "- Bash rm -rf /" }
)
check(
  "no reply says why",
  claude_task.result_lines({ subtype = "error_max_turns" }),
  { "(Claude finished without a reply: error_max_turns)" }
)

check("failure by exit code", claude_task.failure_message(2, 0, "bad flag\n"), "claude: task failed (exit 2)\nbad flag")
check("failure by signal", claude_task.failure_message(0, 9, ""), "claude: task failed (killed by signal 9)")
check("elapsed time", claude_task.format_elapsed(102), "1:42")
check("indicator line", claude_task.indicator_line(5, "Edit a.py"), " claude 0:05 · Edit a.py ")

if failures > 0 then
  print(failures .. " failed")
  os.exit(1)
end
print("all passed")
