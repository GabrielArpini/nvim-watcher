local memory = require('nvim-watcher.memory')

local M = {}

local function paths()
  local home = vim.env.HOME or ''
  local base = vim.env.XDG_CONFIG_HOME or (home .. '/.config')
  return {
    { scope = 'local', path = vim.fn.getcwd() .. '/.nvim-watcher/memory.jsonl' },
    { scope = 'global', path = base .. '/nvim-watcher/memory.jsonl' },
  }
end

local function read_jsonl(path)
  local entries = {}
  if vim.fn.filereadable(path) == 0 then return entries end
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

local function key_for(entry)
  local ctx = entry.context or {}
  return ctx.question or (ctx.diagnostic and ctx.diagnostic.message) or '(no question)'
end

local function group(entries)
  local groups = {}
  for _, e in ipairs(entries) do
    local k = key_for(e)
    local g = groups[k]
    if not g then
      g = { question = k, apply = 0, consent = 0, negate = 0, total = 0, last_ts = '' }
      groups[k] = g
    end
    g[e.action or 'unknown'] = (g[e.action or 'unknown'] or 0) + 1
    g.total = g.total + 1
    if (e.ts or '') > g.last_ts then g.last_ts = e.ts or '' end
  end
  local list = {}
  for _, g in pairs(groups) do table.insert(list, g) end
  table.sort(list, function(a, b) return a.total > b.total end)
  return list
end

local function render(all_entries, scope_label)
  local lines = {}
  table.insert(lines, '# nvim-watcher memory')
  table.insert(lines, '')
  table.insert(lines, string.format('scope shown: %s | entries: %d', scope_label, #all_entries))
  local totals = { apply = 0, consent = 0, negate = 0 }
  for _, e in ipairs(all_entries) do
    if totals[e.action] then totals[e.action] = totals[e.action] + 1 end
  end
  table.insert(lines, string.format('apply %d | consent %d | negate %d', totals.apply, totals.consent, totals.negate))
  table.insert(lines, '')
  table.insert(lines, '## Most acted')
  table.insert(lines, '')
  local grouped = group(all_entries)
  if #grouped == 0 then
    table.insert(lines, '(empty)')
  else
    for _, g in ipairs(grouped) do
      table.insert(lines, string.format('apply %-3d consent %-3d negate %-3d  %s',
        g.apply or 0, g.consent or 0, g.negate or 0, g.question))
    end
  end
  table.insert(lines, '')
  table.insert(lines, '## Recent (last 20)')
  table.insert(lines, '')
  local recent = {}
  for i = math.max(1, #all_entries - 19), #all_entries do
    table.insert(recent, all_entries[i])
  end
  for _, e in ipairs(recent) do
    local ctx = e.context or {}
    local q = ctx.question or (ctx.diagnostic and ctx.diagnostic.message) or ''
    local reason = e.reason and (' -- ' .. e.reason) or ''
    table.insert(lines, string.format('%s  %-8s %s%s', e.ts or '?', e.action or '?', q, reason))
  end
  return lines
end

function M.open()
  local all = {}
  local shown = {}
  for _, p in ipairs(paths()) do
    local entries = read_jsonl(p.path)
    if #entries > 0 then
      table.insert(shown, string.format('%s (%d)', p.scope, #entries))
      for _, e in ipairs(entries) do table.insert(all, e) end
    end
  end
  local label = #shown > 0 and table.concat(shown, ', ') or ('active=' .. memory.scope())
  local lines = render(all, label)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.api.nvim_open_win(buf, true, { split = 'right' })
end

return M
