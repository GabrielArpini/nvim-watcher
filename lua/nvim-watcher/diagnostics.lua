local M = {}

local severity_name = {
  [vim.diagnostic.severity.ERROR] = 'ERROR',
  [vim.diagnostic.severity.WARN] = 'WARN',
  [vim.diagnostic.severity.INFO] = 'INFO',
  [vim.diagnostic.severity.HINT] = 'HINT',
}

function M.pick_nearest(bufnr, cursor_line)
  local diags = vim.diagnostic.get(bufnr, {
    severity = { min = vim.diagnostic.severity.WARN },
  })
  if #diags == 0 then
    return nil
  end

  table.sort(diags, function(a, b)
    local da = math.abs(a.lnum - cursor_line)
    local db = math.abs(b.lnum - cursor_line)
    if da ~= db then
      return da < db
    end
    return a.severity < b.severity
  end)

  local d = diags[1]
  return {
    message = d.message,
    source = d.source or 'lsp',
    severity = severity_name[d.severity] or tostring(d.severity),
    lnum = d.lnum,
    raw = d,
    bufnr = bufnr,
  }
end

return M
