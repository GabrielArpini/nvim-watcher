local trigger = require('nvim-watcher.trigger')

local M = {}

local did_setup = false

function M.setup(opts)
  if did_setup then return end
  did_setup = true

  trigger.setup(opts)

  vim.api.nvim_create_user_command('WatcherTrigger', function()
    trigger.summon()
  end, { desc = 'nvim-watcher: force popup now' })

  vim.api.nvim_create_user_command('WatcherClose', function()
    require('nvim-watcher.popup').close()
  end, { desc = 'nvim-watcher: close popup' })
end

return M
