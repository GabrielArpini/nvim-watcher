local log = require('nvim-watcher.log')

local M = {}

local function to_lsp_diagnostic(d)
  if d.user_data and d.user_data.lsp then
    return d.user_data.lsp
  end
  return {
    range = {
      start = { line = d.lnum or 0, character = d.col or 0 },
      ['end'] = { line = d.end_lnum or d.lnum or 0, character = d.end_col or d.col or 0 },
    },
    message = d.message,
    severity = d.severity,
    source = d.source,
    code = d.code,
  }
end

function M.apply_lsp(diag)
  if not diag then
    vim.notify('nvim-watcher: no diagnostic to apply', vim.log.levels.INFO)
    return false
  end
  local lsp_diag = to_lsp_diagnostic(diag)
  local start_line = (diag.lnum or 0) + 1
  local start_col = diag.col or 0
  local end_line = (diag.end_lnum or diag.lnum or 0) + 1
  local end_col = diag.end_col or start_col

  log.append({
    event = 'apply_lsp_requested',
    message = diag.message,
    source = diag.source,
    lnum = diag.lnum,
  })

  vim.lsp.buf.code_action({
    context = { diagnostics = { lsp_diag } },
    range = {
      start = { start_line, start_col },
      ['end'] = { end_line, end_col },
    },
    apply = true,
  })
  return true
end

return M
