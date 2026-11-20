# 💾 neovim config

_it configures neovim_

### Setup

First, install Neovim.

```
brew install neovim
```

Also, install `ripgrep` (a dependency of Telescope), `tree-sitter-cli` (used by
nvim-treesitter to build parsers), and `node` (used by Mason to install
pyright, ts_ls, and prettier).

```
brew install ripgrep tree-sitter-cli node
```

Then, clone this repository into your `~/.config` directory.
On first starting neovim with `nvim`, `lazy.nvim` will install itself and all
necessary plugins at the versions in `lazy-lock.json`. Mason then installs the
LSPs and formatters listed in `lua/plugins/lsp_config/init.lua`.

### Plugin versions

`lazy-lock.json` is committed so every machine uses the same plugin versions.

- Update plugins on one machine only (`:Lazy update`), then commit the lockfile.
- On other machines, run `:Lazy restore` after pulling. lazy.nvim only applies
  the lockfile automatically on a fresh install.

### Local configuration

Defaults live in `lua/config/_base_config.toml`. Override them in a
`.nvim_config.toml`, which should stay untracked. Files are merged in this
order, later ones winning:

1. `~/.config/nvim/.nvim_config.toml`
2. `~/.nvim_config.toml`
3. the nearest `.nvim_config.toml` at or above the directory nvim starts in

The third lets a repository carry its own settings. For example, a repo that
type checks with pyrefly and lints with flake8:

```toml
[lsp_config.python]
type_checker = "pyrefly"   # default "pyright"
ruff_lint = false          # hide ruff's lint diagnostics

[lint.linters_by_ft]
python = ["flake8"]        # any nvim-lint linter names

[lint.linters.flake8]
root_markers = [".flake8"] # run from the directory holding this file
prefer_venv = true         # use .venv/bin/flake8 if one exists
extra_args = []            # arguments placed before the defaults
```

The TOML parser (`lua/vendor/toml.lua`) supports TOML 0.4: use `[table]`
headers rather than dotted keys.

Python is formatted with ruff (`ruff format` plus import sorting). ruff,
pyrefly, and linters marked `prefer_venv` run from the nearest `.venv` that
contains them, so their versions match the project's pins.

`:Prek` (`<leader>k`) runs the repo's pre-commit hooks on the current file
with `prek`, through `mise exec` when mise is installed.

### Claude keymaps

These hand code to a throwaway headless [Claude Code](https://claude.com/claude-code) session. They need
`claude` on `PATH`.

| Key | Command | What it does |
|---|---|---|
| `<leader>e` | `:Rundown` | Explains the current line or selection in a floating window. |
| `<leader>a` | `:ClaudeTask` | Opens a buffer for an instruction, then carries it out with the current line or selection, and the diagnostics on it, as context. `<C-s>` sends it. |
| `<leader>A` | `:ClaudeReply` | Jumps into the latest reply, reopening it if it was closed. `:ClaudeReply 2` opens the one before it. |
| | `:ClaudeTaskCancel` | Stops running tasks. |

In a reply window, `q` closes it and `c` continues the session as an interactive chat in a new terminal
window. `c` needs `lemonaid`.

- **Tasks run unattended.** A task uses Claude's auto permission mode: it edits files and runs shell
  commands without asking. The reply lists anything that mode refused, and the files that changed
  according to git. Tasks are stopped when neovim exits.
- **Tasks are limited.** A task gets no MCP servers, stops after spending `vim.g.claude_task_max_usd`
  (default 5) and is stopped after `vim.g.claude_task_timeout_minutes` (default 30).
- **Every rundown and task is saved** as a Claude session, so that `c` can resume it.
- **The rundown's output format** comes from a `rundown` skill in `~/.claude/skills`, which is not part
  of this repository. Without it, `:Rundown` has no instructions to follow.
- **Models.** Set `vim.g.rundown_model` (default `sonnet`) or `vim.g.claude_task_model` (default:
  Claude's own default) to change them.

The logic is in pure functions with tests: `nvim -l tests/claude_helpers_test.lua`.

### Acknowledgments

h/t to YouTube user [typecraft](https://www.youtube.com/@typecraft_dev) for his awesome [video series](https://www.youtube.com/playlist?list=PLsz00TDipIffreIaUNk64KxTIkQaGguqn) on getting set up in
neovim, which I followed pretty closely as I was getting started.

