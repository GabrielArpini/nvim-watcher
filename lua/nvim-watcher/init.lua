local trigger = require('nvim-watcher.trigger')
local memory = require('nvim-watcher.memory')
local popup = require('nvim-watcher.popup')
local model = require('nvim-watcher.model')
local privacy = require('nvim-watcher.privacy')
local skeleton = require('nvim-watcher.skeleton')

local M = {}

local did_setup = false

function M.setup(opts)
  if did_setup then return end
  did_setup = true
  opts = opts or {}

  memory.setup({ scope = opts.memory_scope or 'local' })
  popup.setup({ keymap_prefix = opts.keymap_prefix })
  model.setup(opts.model or {})
  privacy.setup(opts.privacy or {})
  skeleton.setup(opts.skeleton or {})
  trigger.setup(opts)

  vim.api.nvim_create_user_command('WatcherTrigger', function()
    trigger.summon()
  end, { desc = 'nvim-watcher: force popup now' })

  vim.api.nvim_create_user_command('WatcherClose', function()
    popup.close()
  end, { desc = 'nvim-watcher: close popup' })

  vim.api.nvim_create_user_command('WatcherRebuildSkeleton', function()
    local start = vim.uv.hrtime()
    skeleton.invalidate('')
    skeleton.build()
    local ms = math.floor((vim.uv.hrtime() - start) / 1e6)
    vim.notify(string.format('nvim-watcher: skeleton built in %d ms', ms), vim.log.levels.INFO)
  end, { desc = 'nvim-watcher: rebuild repo skeleton' })

  vim.api.nvim_create_user_command('WatcherSkeleton', function()
    local text = skeleton.get_skeleton({ current_file = vim.fn.expand('%:.') })
    if not text then
      vim.notify('nvim-watcher: skeleton empty or disabled', vim.log.levels.INFO)
      return
    end
    local lines = vim.split(text, '\n')
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_open_win(buf, true, { split = 'right' })
  end, { desc = 'nvim-watcher: show current repo skeleton' })

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('NvimWatcherSkeleton', { clear = true }),
    callback = function(args)
      local root = skeleton.root()
      if not root then return end
      local full = vim.api.nvim_buf_get_name(args.buf)
      if full:sub(1, #root + 1) == root .. '/' then
        skeleton.invalidate(full:sub(#root + 2))
      end
    end,
  })

  local function action_cmd(name, key)
    vim.api.nvim_create_user_command(name, function()
      if not popup.is_open() then
        vim.notify('nvim-watcher: no popup open', vim.log.levels.INFO)
        return
      end
      popup.actions()[key]()
    end, { desc = 'nvim-watcher: ' .. key })
  end

  vim.api.nvim_create_user_command('WatcherLastPrompt', function()
    local last = model.last()
    if not last or not last.prompt then
      vim.notify('nvim-watcher: no prompt sent yet', vim.log.levels.INFO)
      return
    end
    local lines = {
      string.format('# last prompt (file=%s, ts=%s, truncated=%s)', last.file or '?', last.ts or '?', tostring(last.truncated)),
      '',
      '## user prompt',
      '',
    }
    for _, l in ipairs(vim.split(last.prompt, '\n')) do table.insert(lines, l) end
    table.insert(lines, '')
    table.insert(lines, '## response')
    table.insert(lines, '')
    for _, l in ipairs(vim.split(last.response or '(none)', '\n')) do table.insert(lines, l) end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = 'markdown'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].modifiable = false
    vim.api.nvim_open_win(buf, true, { split = 'right' })
  end, { desc = 'nvim-watcher: show last model prompt and response' })

  vim.api.nvim_create_user_command('WatcherMemory', function()
    require('nvim-watcher.browser').open()
  end, { desc = 'nvim-watcher: browse memory' })

  action_cmd('WatcherApply', 'apply')
  action_cmd('WatcherConsent', 'consent')
  action_cmd('WatcherNegate', 'negate')
  action_cmd('WatcherIgnore', 'ignore')
end

return M
