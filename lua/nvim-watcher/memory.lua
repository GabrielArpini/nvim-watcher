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
  if scope == 'global' then
    return global_path()
  end
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

local function read_jsonl(path)
  local entries = {}
  if vim.fn.filereadable(path) == 0 then
    return entries
  end
  for _, line in ipairs(vim.fn.readfile(path)) do
    if line ~= '' then
      local ok, decoded = pcall(vim.fn.json_decode, line)
      if ok and type(decoded) == 'table' then
        table.insert(entries, decoded)
      end
    end
  end
  return entries
end

function M.all()
  local home = vim.env.HOME or ''
  local base = vim.env.XDG_CONFIG_HOME or (home .. '/.config')
  local paths = {
    vim.fn.getcwd() .. '/.nvim-watcher/memory.jsonl',
    base .. '/nvim-watcher/memory.jsonl',
  }
  local entries = {}
  for _, p in ipairs(paths) do
    for _, e in ipairs(read_jsonl(p)) do
      table.insert(entries, e)
    end
  end
  table.sort(entries, function(a, b)
    return (a.ts or '') < (b.ts or '')
  end)
  return entries
end

local function question_of(e)
  local ctx = e.context or {}
  return ctx.question or (ctx.diagnostic and ctx.diagnostic.message) or ''
end

function M.feedback_section(opts)
  opts = opts or {}
  local others_budget = opts.others_char_budget or 400
  local all = M.all()

  local negates, others = {}, {}
  for i = #all, 1, -1 do
    local e = all[i]
    if e.action == 'negate' then
      table.insert(negates, e)
    elseif e.action == 'consent' or e.action == 'apply' then
      table.insert(others, e)
    end
  end

  if #negates == 0 and #others == 0 then
    return nil
  end

  local lines = {}
  local seen = {}

  if #negates > 0 then
    table.insert(lines, 'Rejected previously, do NOT raise again (hard rules):')
    for _, e in ipairs(negates) do
      local q = question_of(e)
      if q ~= '' and not seen[q] then
        seen[q] = true
        local reason = e.reason and (' (reason: ' .. e.reason .. ')') or ''
        table.insert(lines, '- ' .. q .. reason)
      end
    end
    table.insert(lines, '')
  end

  local used = 0
  local appr = {}
  for _, e in ipairs(others) do
    local q = question_of(e)
    if q ~= '' and not seen[q] then
      local entry = '- ' .. q
      if used + #entry + 1 > others_budget then
        break
      end
      seen[q] = true
      used = used + #entry + 1
      table.insert(appr, entry)
    end
  end
  if #appr > 0 then
    table.insert(lines, 'Already acknowledged, do NOT repeat:')
    for _, l in ipairs(appr) do
      table.insert(lines, l)
    end
  end

  return table.concat(lines, '\n')
end

return M
