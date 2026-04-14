local M = {}

local function log_dir()
  local cwd = vim.fn.getcwd()
  return cwd .. '/.nvim-watcher'
end

local function ensure_dir()
  local dir = log_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
  return dir
end

function M.append(event)
  local dir = ensure_dir()
  local path = dir .. '/log.jsonl'
  event.ts = os.date('!%Y-%m-%dT%H:%M:%SZ')
  local line = vim.fn.json_encode(event)
  local f = io.open(path, 'a')
  if not f then
    vim.notify('nvim-watcher: failed to open log at ' .. path, vim.log.levels.WARN)
    return
  end
  f:write(line .. '\n')
  f:close()
end

return M
