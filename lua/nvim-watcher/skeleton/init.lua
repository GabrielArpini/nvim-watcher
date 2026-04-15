local extract = require('nvim-watcher.skeleton.extract')
local graph_mod = require('nvim-watcher.skeleton.graph')
local pack = require('nvim-watcher.skeleton.pack')

local M = {}

local config = {
  enabled = true,
  max_tokens = 2000,
  max_files = 2000,
}

local state = {
  cache = {},
  graph = nil,
  root = nil,
  built = false,
}

function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    config[k] = v
  end
end

function M.is_enabled()
  return config.enabled == true
end

local function repo_root()
  local cwd = vim.fn.getcwd()
  local res = vim.fn.systemlist({ 'git', '-C', cwd, 'rev-parse', '--show-toplevel' })
  if vim.v.shell_error == 0 and res[1] and res[1] ~= '' then
    return res[1]
  end
  return cwd
end

local function list_tracked_files(root)
  local res = vim.fn.systemlist({ 'git', '-C', root, 'ls-files' })
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return res
end

local function file_mtime(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.mtime and stat.mtime.sec or 0
end

local function rel(path, root)
  if path:sub(1, #root + 1) == root .. '/' then
    return path:sub(#root + 2)
  end
  return path
end

function M.build()
  local root = repo_root()
  state.root = root
  local files = list_tracked_files(root)
  if #files == 0 then
    state.built = true
    state.graph = graph_mod.build({})
    state.cache = {}
    return
  end
  if #files > config.max_files then
    vim.notify(
      string.format(
        'nvim-watcher: skeleton skipped, %d files > max_files=%d',
        #files,
        config.max_files
      ),
      vim.log.levels.WARN
    )
    state.built = true
    state.graph = graph_mod.build({})
    return
  end
  local file_tags = {}
  for _, relpath in ipairs(files) do
    local lang = extract.lang_for(relpath)
    if lang then
      local abspath = root .. '/' .. relpath
      local mtime = file_mtime(abspath)
      local cached = state.cache[relpath]
      if cached and cached.mtime == mtime then
        file_tags[relpath] = cached.tags
      else
        local tags, err = extract.extract_from_path(abspath, lang)
        if not err and tags then
          state.cache[relpath] = { tags = tags, mtime = mtime }
          file_tags[relpath] = tags
        end
      end
    end
  end
  state.graph = graph_mod.build(file_tags)
  state.built = true
end

function M.invalidate(relpath)
  state.cache[relpath] = nil
  state.built = false
end

local function ensure_built()
  if not state.built then
    M.build()
  end
end

function M.get_skeleton(opts)
  opts = opts or {}
  if not M.is_enabled() then
    return nil
  end
  ensure_built()
  if not state.graph or #state.graph.nodes == 0 then
    return nil
  end

  local current_file = opts.current_file
  local personalization = {}
  if current_file then
    personalization[current_file] = 10.0
  end
  if opts.extra_focus then
    for f, w in pairs(opts.extra_focus) do
      personalization[f] = (personalization[f] or 0) + w
    end
  end

  local rank = graph_mod.pagerank(state.graph, personalization)
  local file_tags = {}
  for f, entry in pairs(state.cache) do
    file_tags[f] = entry.tags
  end
  local text, tokens =
    pack.render(file_tags, rank, opts.max_tokens or config.max_tokens, current_file)
  return text, tokens
end

function M.root()
  return state.root or repo_root()
end

return M
