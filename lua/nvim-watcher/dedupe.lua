local M = {}

local state = {
  identity = nil,
  ignored = false,
}

local function make_identity(diag)
  if not diag then
    return nil
  end
  return string.format(
    '%s|%s|%s',
    tostring(diag.source or ''),
    tostring(diag.message or ''),
    tostring(diag.lnum or '')
  )
end

function M.should_suppress(diag)
  local id = make_identity(diag)
  if not id then
    return false
  end
  if state.identity == id and state.ignored then
    return true
  end
  return false
end

function M.remember(diag, action)
  local id = make_identity(diag)
  if not id then
    state.identity = nil
    state.ignored = false
    return
  end
  state.identity = id
  state.ignored = action == 'ignore'
end

function M.reset()
  state.identity = nil
  state.ignored = false
end

return M
