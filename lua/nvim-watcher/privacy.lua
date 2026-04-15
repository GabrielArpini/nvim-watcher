local M = {}

local DEFAULT_IGNORE_GLOBS = {
  '.env',
  '.env.*',
  '*.env',
  '**/secrets/**',
  '**/secret/**',
  '**/.ssh/**',
  'id_rsa*',
  'id_ecdsa*',
  'id_ed25519*',
  '*.pem',
  '*.key',
  '*.p12',
  '*.pfx',
  '*.crt',
  'credentials.json',
  'service-account*.json',
  '*-credentials.json',
  '.aws/**',
  '.gcloud/**',
  '.config/gcloud/**',
  '.netrc',
  '.git-credentials',
  '*.keystore',
  '*.jks',
}

local config = {
  extra_ignore_patterns = {},
  redact = true,
  strict = false,
}

local compiled_ignore = {}

local function compile_patterns()
  compiled_ignore = {}
  local all = {}
  for _, g in ipairs(DEFAULT_IGNORE_GLOBS) do
    table.insert(all, g)
  end
  for _, g in ipairs(config.extra_ignore_patterns or {}) do
    table.insert(all, g)
  end
  for _, g in ipairs(all) do
    local ok, rx = pcall(vim.fn.glob2regpat, g)
    if ok then
      table.insert(compiled_ignore, { glob = g, regex = rx })
    end
  end
end

function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    config[k] = v
  end
  compile_patterns()
end

function M.is_blocked_path(relpath)
  if not relpath or relpath == '' then
    return false, nil
  end
  local basename = vim.fn.fnamemodify(relpath, ':t')
  for _, entry in ipairs(compiled_ignore) do
    if vim.fn.match(relpath, entry.regex) >= 0 or vim.fn.match(basename, entry.regex) >= 0 then
      return true, entry.glob
    end
  end
  return false, nil
end

local REDACTIONS = {
  { kind = 'aws_access_key', pattern = 'AKIA[0-9A-Z]+' },
  { kind = 'github_token', pattern = 'gh[pousr]_[A-Za-z0-9]+' },
  { kind = 'jwt', pattern = 'eyJ[A-Za-z0-9_%-]+%.[A-Za-z0-9_%-]+%.[A-Za-z0-9_%-]+' },
  {
    kind = 'private_key_block',
    pattern = '%-%-%-%-%-BEGIN[^\n]-PRIVATE KEY%-%-%-%-%-.-%-%-%-%-%-END[^\n]-PRIVATE KEY%-%-%-%-%-',
  },
  {
    kind = 'secret_assignment',
    pattern = '[Aa][Pp][Ii][_%-]?[Kk][Ee][Yy]%s*[=:]%s*["\'][^"\']+["\']',
  },
  { kind = 'secret_assignment', pattern = '[Ss][Ee][Cc][Rr][Ee][Tt]%s*[=:]%s*["\'][^"\']+["\']' },
  { kind = 'secret_assignment', pattern = '[Tt][Oo][Kk][Ee][Nn]%s*[=:]%s*["\'][^"\']+["\']' },
  {
    kind = 'secret_assignment',
    pattern = '[Pp][Aa][Ss][Ss][Ww]?[Oo]?[Rr]?[Dd]?%s*[=:]%s*["\'][^"\']+["\']',
  },
  { kind = 'bearer', pattern = '[Bb]earer%s+[A-Za-z0-9%-_%.]+' },
}

function M.redact(text)
  if not text or text == '' then
    return text, 0
  end
  local count = 0
  local out = text
  for _, r in ipairs(REDACTIONS) do
    local replaced, n = out:gsub(r.pattern, '[REDACTED:' .. r.kind .. ']')
    out = replaced
    count = count + n
  end
  return out, count
end

function M.should_redact()
  return config.redact == true
end

function M.is_strict()
  return config.strict == true
end

compile_patterns()

return M
