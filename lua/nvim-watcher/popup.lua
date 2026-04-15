local log = require('nvim-watcher.log')
local memory = require('nvim-watcher.memory')
local actions = require('nvim-watcher.actions')
local dedupe = require('nvim-watcher.dedupe')

local M = {}

local config = {
  keymap_prefix = '<leader>w',
}

local state = {
  buf = nil,
  win = nil,
  augroup = nil,
  current_opts = nil,
  global_keys = {},
}

local function unbind_global_keys()
  for _, key in ipairs(state.global_keys) do
    pcall(vim.keymap.del, 'n', key)
  end
  state.global_keys = {}
end

local function close()
  unbind_global_keys()
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.buf = nil
  state.win = nil
  state.current_opts = nil
end

local function build_context(opts)
  local ctx = {
    file = vim.fn.expand('%:.'),
    source = opts.source,
    question = opts.question,
    reasoning = opts.reasoning,
  }
  if opts.diagnostic then
    ctx.lnum = opts.diagnostic.lnum
    ctx.diagnostic = {
      message = opts.diagnostic.message,
      source = opts.diagnostic.source,
      severity = opts.diagnostic.severity,
      lnum = opts.diagnostic.lnum,
    }
  end
  return ctx
end

local function write_memory(action, opts, reason)
  local entry = {
    action = action,
    context = opts and build_context(opts) or nil,
  }
  if reason and reason ~= '' then
    entry.reason = reason
  end
  memory.append(entry)
end

local function respond(action, extra)
  if not M.is_open() then
    return
  end
  local opts = state.current_opts
  local event = { event = 'response', action = action }
  if extra then
    for k, v in pairs(extra) do
      event[k] = v
    end
  end
  log.append(event)

  if action == 'apply' or action == 'consent' or action == 'negate' then
    local reason = (action == 'negate' and extra and extra.reason) or nil
    write_memory(action, opts, reason)
  end

  if opts and opts.source == 'lsp_diagnostic' and opts.diagnostic then
    dedupe.remember(opts.diagnostic, action)
  end

  local do_after_close
  if
    action == 'apply'
    and opts
    and opts.source == 'lsp_diagnostic'
    and opts.diagnostic
    and opts.diagnostic.raw
  then
    local raw = opts.diagnostic.raw
    local bufnr = opts.bufnr or 0
    do_after_close = function()
      actions.apply_lsp(raw, bufnr)
    end
  end

  close()
  if do_after_close then
    vim.schedule(do_after_close)
  end
end

local function do_apply()
  respond('apply')
end
local function do_consent()
  respond('consent')
end
local function do_negate()
  vim.ui.input({ prompt = 'Why reject? ' }, function(reason)
    respond('negate', { reason = reason or '' })
  end)
end
local function do_ignore()
  respond('ignore')
end

function M.setup(opts)
  opts = opts or {}
  if opts.keymap_prefix ~= nil then
    config.keymap_prefix = opts.keymap_prefix
  end
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.actions()
  return {
    apply = do_apply,
    consent = do_consent,
    negate = do_negate,
    ignore = do_ignore,
  }
end

local function bind_global_keys()
  local prefix = config.keymap_prefix
  if not prefix or prefix == false then
    return
  end
  local keys = {
    { prefix .. 'a', do_apply, 'nvim-watcher: apply' },
    { prefix .. 'c', do_consent, 'nvim-watcher: consent' },
    { prefix .. 'n', do_negate, 'nvim-watcher: negate' },
    { prefix .. 'i', do_ignore, 'nvim-watcher: ignore' },
  }
  for _, k in ipairs(keys) do
    vim.keymap.set('n', k[1], k[2], { silent = true, desc = k[3] })
    table.insert(state.global_keys, k[1])
  end
end

function M.open(opts)
  if M.is_open() then
    return
  end
  opts = opts or {}
  opts.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local question = opts.question or 'This is a placeholder question about your code.'
  local reasoning = opts.reasoning
    or 'Placeholder reasoning: model would explain why it flagged this.'

  local prefix = config.keymap_prefix or ''
  local hints
  if prefix ~= '' then
    hints = string.format(
      '  [%sa] Apply  [%sc] Consent  [%sn] Negate  [%si] Ignore',
      prefix,
      prefix,
      prefix,
      prefix
    )
  else
    hints = '  :WatcherApply  :WatcherConsent  :WatcherNegate  :WatcherIgnore'
  end

  local lines = {
    '  nvim-watcher ',
    '',
    '  Question:',
    '    ' .. question,
    '',
    '  Reasoning:',
    '    ' .. reasoning,
    '',
    hints,
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'nvim-watcher'

  local width = 70
  local height = #lines
  local ui = vim.api.nvim_list_uis()[1] or { width = 100, height = 40 }
  local col = ui.width - width - 2
  local row = 1

  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    focusable = true,
    noautocmd = true,
  })

  state.buf = buf
  state.win = win
  state.current_opts = opts

  local function map(key, fn)
    vim.keymap.set('n', key, fn, { buffer = buf, nowait = true, silent = true })
  end

  map('a', do_apply)
  map('c', do_consent)
  map('n', do_negate)
  map('<Esc>', do_ignore)
  map('q', do_ignore)

  bind_global_keys()

  state.augroup = vim.api.nvim_create_augroup('NvimWatcherPopup', { clear = true })

  log.append({ event = 'popup_opened', question = question, source = opts.source })
end

function M.close()
  close()
end

return M
