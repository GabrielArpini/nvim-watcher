local popup = require('nvim-watcher.popup')
local log = require('nvim-watcher.log')
local diagnostics = require('nvim-watcher.diagnostics')
local model = require('nvim-watcher.model')
local privacy = require('nvim-watcher.privacy')
local dedupe = require('nvim-watcher.dedupe')
local skeleton = require('nvim-watcher.skeleton')

local M = {}

local state = {
  timer = nil,
  augroup = nil,
  idle_ms = 7000,
  dirty = false,
  exclude_filetypes = {},
}

local function excluded()
  local ft = vim.bo.filetype
  for _, x in ipairs(state.exclude_filetypes) do
    if x == ft then return true end
  end
  return false
end

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
  if dedupe.should_suppress(d) then
    return nil, 'suppressed_duplicate'
  end
  return {
    question = d.message,
    reasoning = string.format('LSP (%s, severity=%s) at line %d', d.source, d.severity, d.lnum + 1),
    source = 'lsp_diagnostic',
    diagnostic = d,
    bufnr = bufnr,
  }
end

local function build_model_ctx()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local file = vim.fn.expand('%:.')
  local raw_code = table.concat(lines, '\n')
  local code = raw_code
  local redaction_count = 0
  if privacy.should_redact() then
    code, redaction_count = privacy.redact(raw_code)
  end
  local ctx = {
    file = file,
    lang = vim.bo[bufnr].filetype,
    code = code,
    cursor_line = cursor[1],
    redaction_count = redaction_count,
  }
  if skeleton.is_enabled() then
    local ok, text = pcall(skeleton.get_skeleton, { current_file = file })
    if ok and text then
      ctx.repo_skeleton = text
    end
  end
  return ctx
end

local function try_model()
  if not model.is_enabled() then return end

  local file = vim.fn.expand('%:.')
  local blocked, matched = privacy.is_blocked_path(file)
  if blocked then
    log.append({ event = 'privacy_blocked_path', file = file, pattern = matched })
    return
  end

  local ctx = build_model_ctx()

  if ctx.redaction_count > 0 then
    if privacy.is_strict() then
      log.append({ event = 'privacy_blocked_content', file = file, redactions = ctx.redaction_count })
      return
    end
    log.append({ event = 'privacy_redacted', file = file, redactions = ctx.redaction_count })
  end

  model.query(ctx, function(result, err)
    if err then
      log.append({ event = 'trigger_fired_silent', cause = 'model_error', err = err })
      return
    end
    if not result then
      log.append({ event = 'trigger_fired_silent', cause = 'model_none' })
      return
    end
    log.append({ event = 'trigger_fired', cause = 'model_flagged', source = 'model' })
    popup.open({
      question = result.question,
      reasoning = result.reasoning,
      source = 'model',
    })
  end)
end

local function fire()
  state.timer = nil
  state.dirty = false
  local lsp_opts, suppress = build_lsp_opts()
  if lsp_opts then
    log.append({ event = 'trigger_fired', cause = 'idle_after_insert_edit', source = lsp_opts.source })
    vim.schedule(function() popup.open(lsp_opts) end)
    return
  end
  if suppress then
    log.append({ event = 'trigger_fired_silent', cause = suppress })
    return
  end
  if model.is_enabled() then
    try_model()
  else
    log.append({ event = 'trigger_fired_silent', cause = 'no_diagnostic' })
  end
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
  state.exclude_filetypes = opts.exclude_filetypes or {
    'markdown', 'gitcommit', 'help', 'text', 'NvimTree', 'oil', 'neo-tree',
  }

  state.augroup = vim.api.nvim_create_augroup('NvimWatcherTrigger', { clear = true })

  vim.api.nvim_create_autocmd('TextChangedI', {
    group = state.augroup,
    callback = function()
      if popup.is_open() then return end
      if excluded() then return end
      state.dirty = true
      restart_timer()
    end,
  })

  vim.api.nvim_create_autocmd('InsertLeave', {
    group = state.augroup,
    callback = function()
      if popup.is_open() then return end
      if excluded() then return end
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
  dedupe.reset()
  local lsp_opts = build_lsp_opts()
  if lsp_opts then
    log.append({ event = 'trigger_fired', cause = 'manual_summon', source = lsp_opts.source })
    popup.open(lsp_opts)
    return
  end
  if model.is_enabled() then
    log.append({ event = 'manual_summon_model' })
    try_model()
    return
  end
  log.append({ event = 'manual_summon_silent', cause = 'no_diagnostic' })
  vim.notify('nvim-watcher: nothing to flag here', vim.log.levels.INFO)
end

return M
