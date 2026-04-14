local M = {}

local config = { scope = 'local' }

local function global_path()
  local base = vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')
  return base .. '/nvim-watcher'
end

local function local_path()
  return vim.fn.getcwd() .. '/.nvim-watcher'
end

local function memory_dir(scope)
  if scope == 'global' then return global_path() end
  return local_path()
end

local function ensure_dir(dir)
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
  return dir
end

local function gen_id()
  return string.format('%d-%d', os.time(), math.random(100000, 999999))
end

function M.setup(opts)
  opts = opts or {}
  config.scope = opts.scope or 'local'
end

function M.append(entry)
  local dir = ensure_dir(memory_dir(config.scope))
  local path = dir .. '/memory.jsonl'
  entry.id = entry.id or gen_id()
  entry.ts = entry.ts or os.date('!%Y-%m-%dT%H:%M:%SZ')
  local f = io.open(path, 'a')
  if not f then
    vim.notify('nvim-watcher: failed to open memory at ' .. path, vim.log.levels.WARN)
    return
  end
  f:write(vim.fn.json_encode(entry) .. '\n')
  f:close()
end

function M.scope()
  return config.scope
end

return M
