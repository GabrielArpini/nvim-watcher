local M = {}

function M.build(file_tags)
  local defs_by_name = {}
  local refs_by_file = {}
  local all_files = {}

  for file, tags in pairs(file_tags) do
    all_files[file] = true
    for _, tag in ipairs(tags) do
      if tag.kind == 'def' then
        defs_by_name[tag.name] = defs_by_name[tag.name] or {}
        table.insert(defs_by_name[tag.name], { file = file, line = tag.line })
      elseif tag.kind == 'ref' then
        refs_by_file[file] = refs_by_file[file] or {}
        refs_by_file[file][tag.name] = (refs_by_file[file][tag.name] or 0) + 1
      end
    end
  end

  local graph = {}
  for from_file, refs in pairs(refs_by_file) do
    for name, count in pairs(refs) do
      local defs = defs_by_name[name]
      if defs and #defs > 0 then
        local share = count / #defs
        for _, d in ipairs(defs) do
          if d.file ~= from_file then
            graph[from_file] = graph[from_file] or {}
            graph[from_file][d.file] = (graph[from_file][d.file] or 0) + share
            all_files[d.file] = true
          end
        end
      end
    end
  end

  local nodes = {}
  for f in pairs(all_files) do
    table.insert(nodes, f)
  end

  return {
    nodes = nodes,
    graph = graph,
    defs_by_name = defs_by_name,
  }
end

function M.pagerank(g, personalization, damping, iterations)
  damping = damping or 0.85
  iterations = iterations or 30
  local nodes = g.nodes
  local graph = g.graph
  local N = #nodes
  if N == 0 then
    return {}
  end

  local p = {}
  local psum = 0
  for _, n in ipairs(nodes) do
    local w = personalization and personalization[n] or 0
    p[n] = w
    psum = psum + w
  end
  if psum == 0 then
    local uniform = 1 / N
    for _, n in ipairs(nodes) do
      p[n] = uniform
    end
  else
    for n, w in pairs(p) do
      p[n] = w / psum
    end
  end

  local rank = {}
  for _, n in ipairs(nodes) do
    rank[n] = 1 / N
  end

  local out_sum = {}
  for from, edges in pairs(graph) do
    local s = 0
    for _, w in pairs(edges) do
      s = s + w
    end
    out_sum[from] = s
  end

  for _ = 1, iterations do
    local dangling_mass = 0
    for _, n in ipairs(nodes) do
      if not out_sum[n] or out_sum[n] == 0 then
        dangling_mass = dangling_mass + rank[n]
      end
    end
    local new_rank = {}
    for _, n in ipairs(nodes) do
      new_rank[n] = (1 - damping) * p[n] + damping * dangling_mass * p[n]
    end
    for from, edges in pairs(graph) do
      local os = out_sum[from]
      if os and os > 0 then
        local contrib = damping * rank[from]
        for to, w in pairs(edges) do
          new_rank[to] = (new_rank[to] or 0) + contrib * (w / os)
        end
      end
    end
    rank = new_rank
  end

  return rank
end

return M
