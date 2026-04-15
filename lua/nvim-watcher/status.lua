local M = {}

local STATES = {
  idle = { label = 'idle', icon = '·' },
  thinking = { label = 'thinking', icon = '…' },
  offline = { label = 'offline', icon = '!' },
  rate_limited = { label = 'rate-limited', icon = '%' },
  disabled = { label = 'off', icon = 'x' },
}

local state = 'disabled'
local since = 0

function M.set(new_state)
  if not STATES[new_state] then
    return
  end
  if state == new_state then
    return
  end
  state = new_state
  since = vim.uv.hrtime()
  vim.schedule(function()
    pcall(vim.cmd, 'redrawstatus')
  end)
end

function M.get()
  return state
end

function M.statusline()
  local s = STATES[state] or STATES.disabled
  return string.format('[watcher %s %s]', s.icon, s.label)
end

return M
