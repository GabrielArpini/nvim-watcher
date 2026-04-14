local M = {}

local plugin_root = nil
local function get_plugin_root()
  if plugin_root then return plugin_root end
  local src = debug.getinfo(1, 'S').source
  if src:sub(1, 1) == '@' then src = src:sub(2) end
  plugin_root = src:gsub('/lua/nvim%-watcher/skeleton/extract%.lua$', '')
  return plugin_root
end

local FILETYPE_TO_LANG = {
  python = 'python',
  typescript = 'typescript',
  javascript = 'javascript',
  typescriptreact = 'tsx',
  javascriptreact = 'javascript',
  lua = 'lua',
  go = 'go',
  rust = 'rust',
  cpp = 'cpp',
  c = 'c',
}

local EXT_TO_LANG = {
  py = 'python', pyi = 'python',
  ts = 'typescript', tsx = 'tsx',
  js = 'javascript', jsx = 'javascript', mjs = 'javascript', cjs = 'javascript',
  lua = 'lua',
  go = 'go',
  rs = 'rust',
  cpp = 'cpp', cc = 'cpp', cxx = 'cpp', hpp = 'cpp', h = 'cpp',
  c = 'c',
}

local query_cache = {}

local function load_query(lang)
  if query_cache[lang] ~= nil then return query_cache[lang] end
  local path = get_plugin_root() .. '/queries/' .. lang .. '/tags.scm'
  local f = io.open(path, 'r')
  if not f then
    query_cache[lang] = false
    return nil
  end
  local src = f:read('*a')
  f:close()
  local ok, q = pcall(vim.treesitter.query.parse, lang, src)
  if not ok then
    query_cache[lang] = false
    return nil
  end
  query_cache[lang] = q
  return q
end

function M.lang_for(path)
  local ext = path:match('%.([^.]+)$')
  if ext then return EXT_TO_LANG[ext:lower()] end
  return nil
end

function M.lang_for_buffer(bufnr)
  local ft = vim.bo[bufnr].filetype
  return FILETYPE_TO_LANG[ft]
end

local function classify_capture(name)
  if name:find('definition%.') or name:find('^definition%.') then return 'def' end
  if name:find('reference%.') or name:find('^reference%.') then return 'ref' end
  return nil
end

function M.extract_from_source(source, lang)
  local q = load_query(lang)
  if not q then return {}, 'no_query_for_lang' end
  local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
  if not ok or not parser then return {}, 'parser_failed' end
  local tree = parser:parse()[1]
  if not tree then return {}, 'parse_failed' end
  local root = tree:root()

  local tags = {}
  for id, node, _ in q:iter_captures(root, source, 0, -1) do
    local cap_name = q.captures[id]
    local kind = classify_capture(cap_name)
    if kind then
      local name_text = vim.treesitter.get_node_text(node, source)
      if name_text and #name_text > 0 and #name_text < 200 then
        local start_row = select(1, node:range())
        table.insert(tags, {
          name = name_text,
          kind = kind,
          line = start_row,
          capture = cap_name,
        })
      end
    end
  end
  return tags, nil
end

function M.extract_from_path(path, lang)
  lang = lang or M.lang_for(path)
  if not lang then return {}, 'unknown_lang' end
  local f = io.open(path, 'r')
  if not f then return {}, 'read_failed' end
  local source = f:read('*a')
  f:close()
  if not source or source == '' then return {}, 'empty' end
  if #source > 1024 * 1024 then return {}, 'too_large' end
  return M.extract_from_source(source, lang)
end

return M
