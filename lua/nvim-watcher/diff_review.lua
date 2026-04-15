local log = require('nvim-watcher.log')
local model = require('nvim-watcher.model')
local privacy = require('nvim-watcher.privacy')
local popup = require('nvim-watcher.popup')
local skeleton = require('nvim-watcher.skeleton')

local M = {}

local config = {
  enabled = true,
  debounce_ms = 3000,
  min_lines = 5,
  max_lines = 500,
}

local state = {
  timer = nil,
  last_hash = nil,
  baselined = false,
  augroup = nil,
}

function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    config[k] = v
  end
end

local function repo_root()
  local res = vim.fn.systemlist({ 'git', 'rev-parse', '--show-toplevel' })
  if vim.v.shell_error ~= 0 or not res[1] or res[1] == '' then
    return nil
  end
  return res[1]
end

local function git_diff(root)
  local res = vim.fn.systemlist({ 'git', '-C', root, 'diff', 'HEAD' })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return table.concat(res, '\n')
end

local function count_changed_lines(diff)
  local n = 0
  for line in diff:gmatch('[^\n]+') do
    local c = line:sub(1, 1)
    if (c == '+' or c == '-') and line:sub(1, 3) ~= '+++' and line:sub(1, 3) ~= '---' then
      n = n + 1
    end
  end
  return n
end

local function hash(s)
  return vim.fn.sha256(s)
end

local function run()
  if not config.enabled then
    return
  end
  local root = repo_root()
  if not root then
    return
  end
  local diff = git_diff(root)
  if not diff or diff == '' then
    return
  end
  local h = hash(diff)
  if h == state.last_hash then
    return
  end

  if not state.baselined then
    state.baselined = true
    state.last_hash = h
    log.append({ event = 'diff_review_baseline', lines = count_changed_lines(diff) })
    return
  end

  local n = count_changed_lines(diff)
  if n < config.min_lines then
    state.last_hash = h
    return
  end
  if n > config.max_lines then
    state.last_hash = h
    log.append({ event = 'diff_review_skipped', reason = 'too_large', lines = n })
    return
  end

  local body = diff
  local redactions = 0
  if privacy.should_redact() then
    body, redactions = privacy.redact(diff)
  end
  if redactions > 0 and privacy.is_strict() then
    state.last_hash = h
    log.append({
      event = 'diff_review_skipped',
      reason = 'strict_redaction',
      redactions = redactions,
    })
    return
  end

  local ctx = {
    file = '(git diff HEAD)',
    lang = 'diff',
    code = body,
    cursor_line = 1,
    redaction_count = redactions,
    review_diff = true,
  }
  if skeleton.is_enabled() then
    local ok, text = pcall(skeleton.get_skeleton, {})
    if ok and text then
      ctx.repo_skeleton = text
    end
  end

  state.last_hash = h
  log.append({ event = 'diff_review_called', lines = n, redactions = redactions })
  model.query(ctx, function(result, err)
    if err then
      log.append({ event = 'diff_review_error', err = err })
      return
    end
    if not result then
      log.append({ event = 'diff_review_silent' })
      return
    end
    log.append({ event = 'diff_review_flagged' })
    popup.open({
      question = result.question,
      reasoning = result.reasoning,
      source = 'diff_review',
    })
  end)
end

local function schedule()
  if state.timer then
    state.timer:stop()
    state.timer:close()
  end
  state.timer = vim.uv.new_timer()
  state.timer:start(
    config.debounce_ms,
    0,
    vim.schedule_wrap(function()
      state.timer = nil
      run()
    end)
  )
end

function M.attach()
  if not config.enabled then
    return
  end
  state.augroup = vim.api.nvim_create_augroup('NvimWatcherDiffReview', { clear = true })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = state.augroup,
    callback = function()
      if popup.is_open() then
        return
      end
      if not model.is_enabled() then
        return
      end
      schedule()
    end,
  })
end

function M.run_now()
  run()
end

return M
