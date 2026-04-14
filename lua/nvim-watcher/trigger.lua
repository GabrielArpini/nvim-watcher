local popup = require('nvim-watcher.popup')
local log = require('nvim-watcher.log')
local diagnostics = require('nvim-watcher.diagnostics')

local M = {}

local state = {
  timer = nil,
  augroup = nil,
  idle_ms = 7000,
  dirty = false,
}

local function cancel_timer()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
end

local function build_lsp_opts()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local d = diagnostics.pick_nearest(bufnr, line)
  if not d then return nil end
  return {
    question = d.message,
    reasoning = string.format('LSP (%s, severity=%s) at line %d', d.source, d.severity, d.lnum + 1),
    source = 'lsp_diagnostic',
    diagnostic = d,
  }
end

local function fire()
  state.timer = nil
  state.dirty = false
  local opts = build_lsp_opts()
  if not opts then
    log.append({ event = 'trigger_fired_silent', cause = 'no_diagnostic' })
    return
  end
  log.append({ event = 'trigger_fired', cause = 'idle_after_insert_edit', source = opts.source })
  vim.schedule(function() popup.open(opts) end)
end

local function restart_timer()
  cancel_timer()
  if not state.dirty then return end
  state.timer = vim.uv.new_timer()
  state.timer:start(state.idle_ms, 0, vim.schedule_wrap(fire))
end

function M.setup(opts)
  opts = opts or {}
  state.idle_ms = opts.idle_ms or 7000

  state.augroup = vim.api.nvim_create_augroup('NvimWatcherTrigger', { clear = true })

  vim.api.nvim_create_autocmd('TextChangedI', {
    group = state.augroup,
    callback = function()
      if popup.is_open() then return end
      state.dirty = true
      restart_timer()
    end,
  })

  vim.api.nvim_create_autocmd('InsertLeave', {
    group = state.augroup,
    callback = function()
      if popup.is_open() then return end
      if state.dirty then restart_timer() end
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    group = state.augroup,
    callback = function()
      if state.timer then
        log.append({ event = 'trigger_cancelled', cause = 'BufLeave' })
        cancel_timer()
      end
    end,
  })
end

function M.summon()
  cancel_timer()
  state.dirty = false
  local opts = build_lsp_opts()
  if not opts then
    log.append({ event = 'manual_summon_silent', cause = 'no_diagnostic' })
    vim.notify('nvim-watcher: nothing to flag here', vim.log.levels.INFO)
    return
  end
  log.append({ event = 'trigger_fired', cause = 'manual_summon', source = opts.source })
  popup.open(opts)
end

return M
