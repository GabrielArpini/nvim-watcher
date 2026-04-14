local log = require('nvim-watcher.log')

local M = {}

local state = {
  buf = nil,
  win = nil,
  augroup = nil,
}

local function close()
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
end

local function respond(action, extra)
  local event = { event = 'response', action = action }
  if extra then
    for k, v in pairs(extra) do event[k] = v end
  end
  log.append(event)
  close()
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.open(opts)
  if M.is_open() then return end
  opts = opts or {}
  local question = opts.question or 'This is a placeholder question about your code.'
  local reasoning = opts.reasoning or 'Placeholder reasoning: model would explain why it flagged this.'

  local lines = {
    '  nvim-watcher ',
    '',
    '  Question:',
    '    ' .. question,
    '',
    '  Reasoning:',
    '    ' .. reasoning,
    '',
    '  [a] Apply   [c] Consent   [n] Negate   [Esc] Ignore',
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'nvim-watcher'

  local width = 60
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

  local function map(key, fn)
    vim.keymap.set('n', key, fn, { buffer = buf, nowait = true, silent = true })
  end

  map('a', function() respond('apply') end)
  map('c', function() respond('consent') end)
  map('n', function()
    vim.ui.input({ prompt = 'Why reject? ' }, function(reason)
      respond('negate', { reason = reason or '' })
    end)
  end)
  map('<Esc>', function() respond('ignore') end)
  map('q', function() respond('ignore') end)

  state.augroup = vim.api.nvim_create_augroup('NvimWatcherPopup', { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertEnter' }, {
    group = state.augroup,
    callback = function(args)
      if args.buf ~= buf then
        respond('ignore', { cause = args.event })
      end
    end,
  })

  log.append({ event = 'popup_opened', question = question })
end

function M.close()
  close()
end

return M
