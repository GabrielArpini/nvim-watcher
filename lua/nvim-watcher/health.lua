local M = {}

local H = vim.health or require('health')
local start = H.start or H.report_start
local ok = H.ok or H.report_ok
local warn = H.warn or H.report_warn
local err = H.error or H.report_error
local info = H.info or H.report_info

local function has(cmd)
  return vim.fn.executable(cmd) == 1
end

local function check_binaries()
  start('nvim-watcher: binaries')
  if has('curl') then
    ok('curl found')
  else
    err('curl not found (required for model calls)')
  end
  if has('git') then
    ok('git found')
  else
    warn('git not found (repo skeleton will fall back to cwd)')
  end
end

local function check_model()
  start('nvim-watcher: model')
  local model_mod = require('nvim-watcher.model')
  if not model_mod.is_enabled() then
    info('model disabled in config (model.enabled = false)')
    return
  end
  local cfg = model_mod.config and model_mod.config() or {}
  local provider = cfg.provider or 'ollama'
  if provider == 'ollama' then
    if not has('curl') then
      err('curl required for ollama calls')
      return
    end
    local url = (cfg.url or 'http://localhost:11434') .. '/api/tags'
    local res = vim.fn.system({ 'curl', '-s', '--max-time', '2', url })
    if vim.v.shell_error ~= 0 or res == '' then
      err('ollama not reachable (is `ollama serve` running?)')
      return
    end
    ok('ollama reachable')
  else
    info('provider: ' .. provider)
    local env = cfg.api_key_env
    if not env or env == '' then
      err('model.api_key_env not set for provider ' .. provider)
      return
    end
    local key = vim.env[env] or os.getenv(env)
    if not key or key == '' then
      err('env var ' .. env .. ' is empty')
      return
    end
    ok('api key present in ' .. env)
  end
end

local function check_treesitter()
  start('nvim-watcher: treesitter parsers')
  local langs = { 'lua', 'python', 'javascript', 'typescript', 'tsx', 'go', 'rust', 'c', 'cpp' }
  local missing = {}
  for _, lang in ipairs(langs) do
    local okp = pcall(vim.treesitter.language.add, lang)
    if not okp then
      table.insert(missing, lang)
    end
  end
  if #missing == 0 then
    ok('all skeleton parsers available')
  else
    warn(
      'missing parsers: '
        .. table.concat(missing, ', ')
        .. ' (files in these languages skip the skeleton)'
    )
  end
end

local function check_queries()
  start('nvim-watcher: tag queries')
  local src = debug.getinfo(1, 'S').source:sub(2)
  local plugin_root = vim.fn.fnamemodify(src, ':h:h:h')
  local qdir = plugin_root .. '/queries'
  if vim.fn.isdirectory(qdir) == 1 then
    ok('queries/ found at ' .. qdir)
  else
    err('queries/ directory not found at ' .. qdir)
  end
end

local function check_storage()
  start('nvim-watcher: storage')
  local cwd = vim.fn.getcwd()
  if vim.fn.filewritable(cwd) == 2 then
    ok('cwd writable (log + local memory)')
  else
    warn('cwd not writable: ' .. cwd)
  end
end

function M.check()
  check_binaries()
  check_model()
  check_treesitter()
  check_queries()
  check_storage()
end

return M
