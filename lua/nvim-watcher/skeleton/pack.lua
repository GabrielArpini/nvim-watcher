local M = {}

local function approx_tokens(s)
  return math.ceil(#s / 4)
end

local function read_line(path, line_1based)
  local f = io.open(path, 'r')
  if not f then return nil end
  local current = 0
  for line in f:lines() do
    current = current + 1
    if current == line_1based then
      f:close()
      return line
    end
    if current > line_1based + 5 then break end
  end
  f:close()
  return nil
end

function M.render(file_tags, rank, max_tokens, current_file)
  max_tokens = max_tokens or 2000

  local scored = {}
  for file, tags in pairs(file_tags) do
    if file ~= current_file then
      local file_rank = rank[file] or 0
      for _, tag in ipairs(tags) do
        if tag.kind == 'def' then
          local kind_weight = 1.0
          if tag.capture:find('class') then kind_weight = 1.5
          elseif tag.capture:find('function') or tag.capture:find('method') then kind_weight = 1.2
          end
          table.insert(scored, {
            file = file,
            line = tag.line,
            name = tag.name,
            capture = tag.capture,
            score = file_rank * kind_weight,
          })
        end
      end
    end
  end

  table.sort(scored, function(a, b) return a.score > b.score end)

  local by_file = {}
  local file_order = {}
  local total = 0
  local header = 'Repo context (symbol outline, not full code):\n'
  total = total + approx_tokens(header)

  for _, t in ipairs(scored) do
    if not by_file[t.file] then
      by_file[t.file] = {}
      table.insert(file_order, t.file)
      total = total + approx_tokens('\n' .. t.file .. '\n')
    end
    local snippet = read_line(t.file, t.line + 1)
    if snippet then
      snippet = snippet:gsub('^%s+', ''):gsub('%s+$', '')
      if #snippet > 140 then snippet = snippet:sub(1, 140) .. '...' end
    else
      snippet = t.name
    end
    local entry = string.format('  %s:%d  %s', t.name, t.line + 1, snippet)
    local cost = approx_tokens(entry .. '\n')
    if total + cost > max_tokens then
      break
    end
    total = total + cost
    table.insert(by_file[t.file], entry)
  end

  local out = { header }
  for _, file in ipairs(file_order) do
    if #by_file[file] > 0 then
      table.insert(out, '\n' .. file)
      for _, entry in ipairs(by_file[file]) do
        table.insert(out, entry)
      end
    end
  end
  return table.concat(out, '\n'), total
end

return M
