local log = require('nvim-watcher.log')
local status = require('nvim-watcher.status')
local memory = require('nvim-watcher.memory')

local M = {}

local last = { prompt = nil, file = nil, ts = nil, truncated = false, response = nil }

local config = {
  enabled = false,
  provider = 'ollama',
  name = 'qwen2.5:0.5b',
  url = 'http://localhost:11434',
  timeout_ms = 10000,
  max_context_chars = 4000,
  api_key_env = nil,
  max_tokens = 256,
}

local SYSTEM_PROMPT = [[You are a code reviewer watching a developer write code in real time.
Your job is to stay silent UNLESS there is a concrete concern worth raising.
Do NOT comment on style, formatting, naming, or minor improvements.
Only speak if you see a likely bug, logic error, or a risky choice.
If the prompt includes "Prior feedback", treat rejections as hard rules: never raise the same or semantically equivalent concern again. Treat acknowledged items as things the developer already knows.

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
  for k, v in pairs(opts) do
    config[k] = v
  end
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
  local feedback = memory.feedback_section({})
  local feedback_section = ''
  if feedback then
    feedback_section = 'Prior feedback from this developer:\n' .. feedback .. '\n\n'
  end
  local user
  if ctx.review_diff then
    user = string.format(
      '%s%sYou are reviewing a working-tree diff (git diff HEAD). Flag concrete concerns only.\n\n```diff\n%s\n```\n\nRespond per the output format.',
      feedback_section,
      skeleton_section,
      code
    )
  else
    user = string.format(
      '%s%sFile: %s\nLanguage: %s\nCursor at line: %d\n\n```%s\n%s\n```\n\nRespond per the output format.',
      feedback_section,
      skeleton_section,
      ctx.file or '(scratch)',
      ctx.lang or 'text',
      ctx.cursor_line or 1,
      ctx.lang or '',
      code
    )
  end
  return user, truncated
end

local function parse_response(text)
  if not text or text == '' then
    return nil
  end
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

local function get_api_key()
  if not config.api_key_env then
    return nil
  end
  return vim.env[config.api_key_env] or os.getenv(config.api_key_env)
end

local function do_curl(url, headers, body, on_done)
  local cmd = {
    'curl',
    '-s',
    '--max-time',
    tostring(math.floor(config.timeout_ms / 1000)),
    '-X',
    'POST',
    url,
    '-H',
    'Content-Type: application/json',
  }
  for _, h in ipairs(headers or {}) do
    table.insert(cmd, '-H')
    table.insert(cmd, h)
  end
  table.insert(cmd, '-d')
  table.insert(cmd, body)
  local started_at = vim.uv.hrtime()
  vim.system(cmd, { text = true }, function(res)
    local latency_ms = math.floor((vim.uv.hrtime() - started_at) / 1e6)
    vim.schedule(function()
      if res.code ~= 0 then
        status.set('offline')
        log.append({
          event = 'model_error',
          stage = 'curl',
          code = res.code,
          stderr = res.stderr,
          latency_ms = latency_ms,
        })
        on_done(nil, 'curl exit ' .. tostring(res.code))
        return
      end
      local raw = res.stdout or ''
      if raw:match('"error"') and raw:lower():match('rate') and raw:lower():match('limit') then
        status.set('rate_limited')
      else
        status.set('idle')
      end
      local ok, decoded = pcall(vim.fn.json_decode, raw)
      if not ok or type(decoded) ~= 'table' then
        log.append({ event = 'model_error', stage = 'decode', raw = raw, latency_ms = latency_ms })
        on_done(nil, 'decode failure')
        return
      end
      log.append({ event = 'model_response_raw', latency_ms = latency_ms })
      on_done(decoded, nil)
    end)
  end)
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
  do_curl(url, {}, body, function(decoded, err)
    if err then
      on_done(nil, err)
      return
    end
    local text = decoded.response or ''
    last.response = text
    on_done(text, nil)
  end)
end

local function call_openai(prompt, on_done)
  local key = get_api_key()
  if not key or key == '' then
    on_done(nil, 'api_key missing (set env var named by model.api_key_env)')
    return
  end
  local url = (config.url or 'https://api.openai.com') .. '/v1/chat/completions'
  local body = vim.fn.json_encode({
    model = config.name,
    temperature = 0.2,
    max_tokens = config.max_tokens,
    messages = {
      { role = 'system', content = SYSTEM_PROMPT },
      { role = 'user', content = prompt },
    },
  })
  do_curl(url, { 'Authorization: Bearer ' .. key }, body, function(decoded, err)
    if err then
      on_done(nil, err)
      return
    end
    local choices = decoded.choices or {}
    local text = choices[1] and choices[1].message and choices[1].message.content or ''
    last.response = text
    on_done(text, nil)
  end)
end

local function call_anthropic(prompt, on_done)
  local key = get_api_key()
  if not key or key == '' then
    on_done(nil, 'api_key missing (set env var named by model.api_key_env)')
    return
  end
  local url = (config.url or 'https://api.anthropic.com') .. '/v1/messages'
  local body = vim.fn.json_encode({
    model = config.name,
    max_tokens = config.max_tokens,
    temperature = 0.2,
    system = SYSTEM_PROMPT,
    messages = { { role = 'user', content = prompt } },
  })
  do_curl(
    url,
    { 'x-api-key: ' .. key, 'anthropic-version: 2023-06-01' },
    body,
    function(decoded, err)
      if err then
        on_done(nil, err)
        return
      end
      local content = decoded.content or {}
      local text = content[1] and content[1].text or ''
      last.response = text
      on_done(text, nil)
    end
  )
end

local function dispatch(prompt, on_done)
  if config.provider == 'ollama' then
    return call_ollama(prompt, on_done)
  elseif config.provider == 'openai' or config.provider == 'openrouter' then
    return call_openai(prompt, on_done)
  elseif config.provider == 'anthropic' then
    return call_anthropic(prompt, on_done)
  end
  on_done(nil, 'unknown provider: ' .. tostring(config.provider))
end

function M.query(ctx, callback)
  if not M.is_enabled() then
    callback(nil, 'disabled')
    return
  end
  local prompt, truncated = build_prompt(ctx)
  last = {
    prompt = prompt,
    file = ctx.file,
    ts = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    truncated = truncated,
    response = nil,
  }
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
      vim.notify(
        'nvim-watcher: file truncated for model (>' .. config.max_context_chars .. ' chars)',
        vim.log.levels.WARN
      )
    end)
  end
  dispatch(prompt, function(raw, err)
    if err then
      callback(nil, err)
      return
    end
    local parsed = parse_response(raw)
    callback(parsed, nil)
  end)
end

function M.last()
  return last
end

function M.config()
  return vim.deepcopy(config)
end

return M
