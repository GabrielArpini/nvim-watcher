[![ci](https://github.com/GabrielArpini/nvim-watcher/actions/workflows/ci.yml/badge.svg)](https://github.com/GabrielArpini/nvim-watcher/actions/workflows/ci.yml)

# nvim-watcher

*No bullshit code companion.*

A dev-first Neovim plugin. The AI watches, questions, and catches mistakes, but never writes code unless you explicitly ask. You own every decision.

**Status:** early design, pre-alpha.

## What makes this different

- No inline suggestions. Ghost text biases your thinking, forbidden here.
- Silent by default. The plugin only speaks when it has something real to say.
- Three-button interactions (Apply, Consent, Negate) that build long-term memory of your coding taste.
- Works with local models (Ollama, llama.cpp) by default. Bring-your-own-API optional.

## Usage

```lua
require('nvim-watcher').setup({
  idle_ms = 7000,
  exclude_filetypes = { 'markdown', 'gitcommit', 'help', 'text' },
  memory_scope = 'local',   -- or 'global'
  keymap_prefix = '<leader>w',
  model = {
    enabled = true,
    provider = 'ollama',
    name = 'qwen2.5:0.5b',
    url = 'http://localhost:11434',
    timeout_ms = 10000,
  },
  privacy = {
    extra_ignore_patterns = {},  -- globs, in addition to built-in defaults
    redact = true,               -- replace obvious secrets before sending
    strict = false,              -- if true, refuse to send any file with redaction hits
  },
  skeleton = {
    enabled = true,
    max_tokens = 2000,           -- rough cap on the repo-context blob
    max_files = 2000,            -- repos larger than this skip the skeleton build
  },
})
```

## Repo skeleton

On first trigger the plugin walks `git ls-files`, extracts symbol
definitions and references via treesitter tag queries, builds a
reference graph between files, and runs personalized PageRank biased
toward the current buffer. Top-ranked symbols are packed into a
`max_tokens`-budget outline and prepended to every model prompt as
`Repo context:`. Per-file tags are cached by mtime and rebuilt
incrementally on `BufWritePost`.

Commands:
- `:WatcherSkeleton` opens the current skeleton in a split.
- `:WatcherRebuildSkeleton` forces a full rebuild and prints elapsed
  time.

Tag query files under `queries/` are vendored from
[aider](https://github.com/Aider-AI/aider) (Apache-2.0). See NOTICE.

Files matching secrets-like globs (`.env*`, `*.key`, `**/secrets/**`,
`**/.ssh/**`, cloud credentials, etc.) are never sent to the model.
When `redact = true` (default), buffer content is scanned before
sending for AWS keys, GitHub tokens, JWTs, private key blocks, and
`api_key`/`token`/`secret`/`password` assignments, and those matches
are replaced with `[REDACTED:kind]`. With `strict = true`, any
redaction hit blocks the whole file instead of just redacting.

Every model prompt is prepended with a "Prior feedback" section:
up to 10 most recent negations (strongest signal, do not re-raise),
then recent consents and applies within an 800-char budget. The
model is instructed to treat rejections as hard rules. See the
block with `:WatcherLastPrompt`.

When the idle trigger fires, the plugin first looks for an LSP
diagnostic near the cursor. If nothing qualifies and a model is
configured, it asks the model. The model is instructed to stay silent
unless there is a concrete concern.

Requires `ollama serve` running locally with the named model pulled.

When a popup is open, respond from anywhere with `<leader>wa` (apply),
`<leader>wc` (consent), `<leader>wn` (negate), `<leader>wi` (ignore).
Or use `:WatcherApply`, `:WatcherConsent`, `:WatcherNegate`,
`:WatcherIgnore`. User responses go to `.nvim-watcher/memory.jsonl`
(local scope) or `~/.config/nvim-watcher/memory.jsonl` (global scope).

When the popup shows an LSP diagnostic, Apply runs the corresponding
LSP code action for that diagnostic. If the server returns exactly
one action it is applied silently, multiple actions open the standard
picker, and "No code actions available" is shown when there is
nothing to do.

If you dismiss a popup without acting on it (Esc, typing, leaving
insert), the same diagnostic (matched by source, message, and line)
will not re-open until its identity changes or you explicitly apply,
consent, or negate. `:WatcherTrigger` always clears this and forces
a fresh popup.

## Last prompt

`:WatcherLastPrompt` opens the exact prompt last sent to the model
(post-redaction, with repo skeleton), plus the raw response. Useful for
verifying privacy redactions and tuning the skeleton budget.

## Memory browser

`:WatcherMemory` opens a split summarizing local + global memory: total
counts per action, grouped counts per question, and the 20 most recent
entries with their reasons.

## Health check

Run `:checkhealth nvim-watcher` to verify curl, git, ollama
reachability, treesitter parsers, vendored queries, and cwd writability.
See `:h nvim-watcher` for the full help doc.

## Statusline

The plugin exposes a tiny state machine at
`require('nvim-watcher.status')` with four states: `idle`, `thinking`,
`offline`, `rate_limited` (plus `disabled` when no model is configured).
Plug it into your statusline:

```lua
-- native statusline
vim.o.statusline = vim.o.statusline .. " %{%v:lua.require'nvim-watcher.status'.statusline()%}"

-- lualine
require('lualine').setup({
  sections = { lualine_x = { require('nvim-watcher.status').statusline } },
})
```

## Not goals

No chat. No autocomplete. No PR reviews. If you want those, use a different plugin.
