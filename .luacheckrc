std = 'lua51+luajit'
globals = { 'vim' }
ignore = {
  '212', -- unused argument
  '213', -- unused loop variable
  '631', -- line too long
}
exclude_files = { 'queries/' }
