local trigger = require('nvim-watcher.trigger')
local memory = require('nvim-watcher.memory')
local popup = require('nvim-watcher.popup')
local model = require('nvim-watcher.model')

local M = {}

local did_setup = false

function M.setup(opts)
  if did_setup then return end
  did_setup = true
  opts = opts or {}

  memory.setup({ scope = opts.memory_scope or 'local' })
  popup.setup({ keymap_prefix = opts.keymap_prefix })
  model.setup(opts.model or {})
  trigger.setup(opts)

  vim.api.nvim_create_user_command('WatcherTrigger', function()
    trigger.summon()
  end, { desc = 'nvim-watcher: force popup now' })

  vim.api.nvim_create_user_command('WatcherClose', function()
    popup.close()
  end, { desc = 'nvim-watcher: close popup' })

  local function action_cmd(name, key)
    vim.api.nvim_create_user_command(name, function()
      if not popup.is_open() then
        vim.notify('nvim-watcher: no popup open', vim.log.levels.INFO)
        return
      end
      popup.actions()[key]()
    end, { desc = 'nvim-watcher: ' .. key })
  end

  action_cmd('WatcherApply', 'apply')
  action_cmd('WatcherConsent', 'consent')
  action_cmd('WatcherNegate', 'negate')
  action_cmd('WatcherIgnore', 'ignore')
end

return M
