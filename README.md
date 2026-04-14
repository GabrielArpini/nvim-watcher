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
  memory_scope = 'local',   -- or 'global'
  keymap_prefix = '<leader>w',
  model = {
    enabled = true,
    provider = 'ollama',
    name = 'qwen2.5:0.5b',
    url = 'http://localhost:11434',
    timeout_ms = 10000,
  },
})
```

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

## Not goals

No chat. No autocomplete. No PR reviews. If you want those, use a different plugin.
