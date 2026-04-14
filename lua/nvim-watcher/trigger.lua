local popup = require('nvim-watcher.popup')
local log = require('nvim-watcher.log')

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

local function fire()
  state.timer = nil
  state.dirty = false
  log.append({ event = 'trigger_fired', cause = 'idle_after_insert_edit' })
  vim.schedule(function() popup.open() end)
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
  log.append({ event = 'trigger_fired', cause = 'manual_summon' })
  popup.open()
end

return M
