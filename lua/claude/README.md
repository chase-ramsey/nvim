# Claude keymaps

Three keymaps that hand code to a throwaway headless [Claude Code](https://claude.com/claude-code)
session and show the reply in a floating window. Nothing here is a chat inside neovim: each request
starts `claude -p`, waits for it to finish, and shows what it said.

| Key | Command | What it does |
|---|---|---|
| `<leader>e` | `:Rundown` | Explains the current line or selection. |
| `<leader>a` | `:ClaudeTask` | Opens a buffer for an instruction, then carries it out with the current line or selection as context. |
| `<leader>A` | `:ClaudeReply` | Jumps into the latest reply, reopening it if it was closed. `:ClaudeReply 2` opens the one before it. |
| | `:ClaudeTaskCancel` | Stops running tasks. |

`<leader>e` and `<leader>a` work in normal mode (current line) and visual mode (selection). The
commands take a range, as in `:10,20Rundown`. The keymaps are set in `lua/vim/keymaps.lua`.

## Requirements

| Tool | Needed for | Without it |
|---|---|---|
| `claude` | Everything | The command reports that it is missing. |
| The `rundown` skill in `~/.claude/skills/rundown` | `:Rundown` | Claude receives `/rundown <file>:<lines>` with no instructions to follow. The skill is not part of this repository. |
| `rg` | The consumer search in `:Rundown` | The search is skipped and Claude searches for itself, which is slower. |
| A treesitter parser for the filetype | The consumer search in `:Rundown` | Same as above. |
| `git` | The changed-file list in a task's reply | Claude lists the files it changed itself. |
| `lemonaid` | `c` in a reply window | The command reports that it is missing. |

## The reply window

Both features show their reply the same way.

- `q` or `<Esc>` closes it.
- `c` closes it and continues the same session as an interactive chat, started with
  `lemonaid lemon start` in a new terminal window. The chat has Claude's normal tools and permission
  mode, whatever the headless session was limited to.
- A reply takes the cursor only when the editor is in normal mode in the window that asked. Otherwise
  it opens in the top-right corner, a message says so, and `<leader>A` jumps into it.
- The last 20 replies are kept for the life of the editor, so one closed by `:only`, or replaced on
  screen by a newer reply, can be reopened with `:ClaudeReply`.

Every rundown and task is saved as a Claude session, because `c` resumes it. Each one therefore
appears in Claude's session list whether or not it is continued.

## Rundown

`:Rundown` answers "what does this code do?" with one sentence and a few short bullets: inputs,
outputs, side effects, who uses it, and anything surprising. The `rundown` skill defines that format.

The session is read-only (`Read`, `Grep` and `Glob`, no MCP servers) and takes about 3.5 seconds. To
let Claude answer in one turn, neovim sends two things with the request:

- **The whole file**, with line numbers, unless it is over 2,000 lines.
- **A consumer search**: `rg` hits for the name of the function or class the selection is in, with two
  lines of context. Treesitter finds that name. A definition that starts inside the selection is
  preferred, so selecting a function together with its decorator names the function. Test files are
  left out unless the selected code is itself in a test file.

Claude still has its read-only tools for what the request does not cover, such as a helper whose
behavior is not clear from its name.

The buffer is saved before the request, because Claude reads the file from disk.

## Task

`:ClaudeTask` opens a floating buffer for an instruction. `<C-s>` sends it, as does `<CR>` in normal
mode; `q` in normal mode cancels. Claude receives the instruction, the selected lines, and the
diagnostics that the editor reports on those lines, so an instruction can be as short as "fix".

**A task runs unattended.** It uses Claude's auto permission mode: it edits files and runs shell
commands without asking, and a classifier refuses what it judges unsafe. Nothing prompts.

While a task runs, a line in the top-right corner shows the elapsed time and the current tool call.
Several tasks can run at once.

The reply holds Claude's summary, followed by:

- **Anything auto mode refused**, under "Blocked by auto mode".
- **The files that changed during the task**, according to git. Neovim snapshots the working tree
  before and after and compares the two. The list includes your own saves in that time. It leaves out
  ignored files and edits inside a submodule.

Limits on a task:

- **No MCP servers**, so it cannot reach connectors such as chat or mail.
- **A spending cap**, $5 by default. The reply says when the cap stopped it.
- **A time limit**, 30 minutes by default. Edits made before then stay on disk, and `c` continues the
  session.
- **Tasks stop when neovim exits**, because only the editor that started a task can show its reply.

Open buffers are reloaded when a task finishes. If a task edits a file that has unsaved changes in
neovim, neovim reports the conflict and you choose.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `vim.g.rundown_model` | `"sonnet"` | Model for rundowns. |
| `vim.g.claude_task_model` | Claude's own default | Model for tasks. |
| `vim.g.claude_task_max_usd` | `5` | Spending cap for one task, in dollars. |
| `vim.g.claude_task_timeout_minutes` | `30` | Time limit for one task. |

## Layout

| File | Contents |
|---|---|
| `session.lua` | What both features share: the reply window, the store of replies, starting a chat, session IDs. |
| `rundown.lua` | `:Rundown`: finding the enclosing definition, the consumer search, the context sent to Claude. |
| `task.lua` | `:ClaudeTask`: the input buffer, diagnostics, running the session, the progress indicator, limits, the changed-file list. |

Each module is written as pure functions followed by the code that touches the editor or starts a
process. In `session.lua` and `task.lua` a comment marks where the second part begins. The pure
functions are exported so the tests can call them.

## Tests

```
nvim -l tests/claude_helpers_test.lua
```

This runs from the repository root, needs no plugins, and covers the pure functions only. It does not
start Claude. The windows, the process handling and the git snapshots were checked by hand in headless
neovim.

## Known limits

- **Rundown bullets can run long.** The skill asks for under 15 words each and the model does not
  always comply. Tune `~/.claude/skills/rundown/SKILL.md`.
- **A common name gives noisy consumer hits.** A function called `run` matches unrelated code. The
  search output is capped at 150 lines.
- **A selection that contains a nested function** searches for consumers of the nested one.
- **Git snapshots run on the main thread.** They took 0.2 seconds on a large monorepo, but a very
  large untracked file that is not ignored would be hashed each time it changes.
- **If the second snapshot fails**, the reply has no file list and does not say why.
