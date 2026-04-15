local log = require('nvim-watcher.log')
local status = require('nvim-watcher.status')

local M = {}

local config = {
  enabled = false,
  provider = 'ollama',
  name = 'qwen2.5:0.5b',
  url = 'http://localhost:11434',
  timeout_ms = 10000,
  max_context_chars = 4000,
}

local SYSTEM_PROMPT = [[You are a code reviewer watching a developer write code in real time.
Your job is to stay silent UNLESS there is a concrete concern worth raising.
Do NOT comment on style, formatting, naming, or minor improvements.
Only speak if you see a likely bug, logic error, or a risky choice.

Output format, strict:
- If nothing is worth flagging, output exactly: NONE
- Otherwise, line 1 is a short question (one sentence, <20 words).
  Line 2 is a short reasoning (one sentence, <30 words).

Examples:

NONE

Why recurse without a base case here?
The function calls itself unconditionally on line 12, which will stack overflow.
]]

function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do config[k] = v end
  status.set(config.enabled and 'idle' or 'disabled')
end

function M.is_enabled()
  return config.enabled == true
end

local function build_prompt(ctx)
  local code = ctx.code or ''
  local truncated = false
  if #code > config.max_context_chars then
    code = code:sub(1, config.max_context_chars)
    truncated = true
  end
  local skeleton_section = ''
  if ctx.repo_skeleton and ctx.repo_skeleton ~= '' then
    skeleton_section = ctx.repo_skeleton .. '\n\n'
  end
  local user = string.format(
    '%sFile: %s\nLanguage: %s\nCursor at line: %d\n\n```%s\n%s\n```\n\nRespond per the output format.',
    skeleton_section,
    ctx.file or '(scratch)',
    ctx.lang or 'text',
    ctx.cursor_line or 1,
    ctx.lang or '',
    code
  )
  return user, truncated
end

local function parse_response(text)
  if not text or text == '' then return nil end
  text = text:gsub('^%s+', ''):gsub('%s+$', '')
  local first_line = text:match('^[^\n]+') or ''
  if first_line:upper():match('^NONE') then
    return nil
  end
  local lines = {}
  for line in text:gmatch('[^\n]+') do
    table.insert(lines, line)
  end
  local question = lines[1] or ''
  local reasoning = table.concat({ unpack(lines, 2) }, ' ')
  if reasoning == '' then
    reasoning = '(no reasoning provided)'
  end
  return { question = question, reasoning = reasoning }
end

local function call_ollama(prompt, on_done)
  local body = vim.fn.json_encode({
    model = config.name,
    system = SYSTEM_PROMPT,
    prompt = prompt,
    stream = false,
    options = { temperature = 0.2 },
  })
  local url = config.url .. '/api/generate'
  local cmd = {
    'curl', '-s', '--max-time', tostring(math.floor(config.timeout_ms / 1000)),
    '-X', 'POST', url,
    '-H', 'Content-Type: application/json',
    '-d', body,
  }
  local started_at = vim.uv.hrtime()
  vim.system(cmd, { text = true }, function(res)
    local latency_ms = math.floor((vim.uv.hrtime() - started_at) / 1e6)
    vim.schedule(function()
      if res.code ~= 0 then
        status.set('offline')
        log.append({ event = 'model_error', stage = 'curl', code = res.code, stderr = res.stderr, latency_ms = latency_ms })
        on_done(nil, 'curl exit ' .. tostring(res.code))
        return
      end
      local raw = res.stdout or ''
      if raw:match('rate') and raw:match('limit') then
        status.set('rate_limited')
      else
        status.set('idle')
      end
      local ok, decoded = pcall(vim.fn.json_decode, res.stdout or '')
      if not ok or type(decoded) ~= 'table' then
        log.append({ event = 'model_error', stage = 'decode', raw = res.stdout, latency_ms = latency_ms })
        on_done(nil, 'decode failure')
        return
      end
      local text = decoded.response or ''
      log.append({ event = 'model_response', raw = text, latency_ms = latency_ms })
      on_done(text, nil)
    end)
  end)
end

function M.query(ctx, callback)
  if not M.is_enabled() then
    callback(nil, 'disabled')
    return
  end
  local prompt, truncated = build_prompt(ctx)
  status.set('thinking')
  log.append({
    event = 'model_called',
    provider = config.provider,
    name = config.name,
    file = ctx.file,
    truncated = truncated,
  })
  if truncated then
    vim.schedule(function()
      vim.notify('nvim-watcher: file truncated for model (>' .. config.max_context_chars .. ' chars)', vim.log.levels.WARN)
    end)
  end
  call_ollama(prompt, function(raw, err)
    if err then
      callback(nil, err)
      return
    end
    local parsed = parse_response(raw)
    callback(parsed, nil)
  end)
end

return M
