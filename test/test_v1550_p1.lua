-- test/test_v1550_p1.lua
-- v1.55.0 — Area 3 Phase 3.5b (slice 1): the nav/headings pop-up. `/` on the nav
-- provider (and the standalone keymaps.nav_search) opens a fuzzy pop-up of the
-- source note's headings; choosing one jumps the source window there. This is
-- "open nav in the pop-up". Driven through nav.search() with vim.ui.select
-- stubbed (no Telescope headless).
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1550_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

require('pkm')   -- ensure setup (min_init did it); nav.setup registered the provider
local nav = require('pkm.nav')

-- A markdown source note in the current window.
local notef = vim.fn.tempname() .. '/src.md'
vim.fn.mkdir(vim.fn.fnamemodify(notef, ':h'), 'p')
vim.fn.writefile({ '# Top', 'x', '## Sub', 'y', '### Deep' }, notef)
vim.cmd('edit ' .. vim.fn.fnameescape(notef))
vim.bo.filetype = 'markdown'
local src_win = vim.api.nvim_get_current_win()

print("== nav.search(): headings pop-up, choosing one jumps the source window ==")
local orig = vim.ui.select
local offered
vim.ui.select = function(items, _opts, cb)
  offered = items
  for _, it in ipairs(items) do if it.value == 3 then cb(it); return end end   -- pick '## Sub'
  cb(nil)
end
nav.search()
vim.ui.select = orig

check("the pop-up offered the headings, level-indented", (function()
  if not offered or #offered ~= 3 then return false end
  return offered[1].display == 'Top'
     and offered[2].display == '  Sub'
     and offered[3].display == '    Deep'
end)(), offered and (#offered .. ' items') or 'nil')
check("heading items carry the source line number", (function()
  return offered and offered[1].value == 1 and offered[2].value == 3 and offered[3].value == 5
end)())
check("choosing '## Sub' jumped the source window to its line (3)",
  vim.api.nvim_win_get_cursor(src_win)[1] == 3,
  tostring(vim.api.nvim_win_get_cursor(src_win)[1]))

print("\n== a note with no headings notifies rather than opening an empty pop-up ==")
vim.cmd('enew')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'no headings here' })
vim.bo.filetype = 'markdown'
local opened = false
vim.ui.select = function() opened = true end
nav.search()
vim.ui.select = orig
check("no headings → no pop-up", not opened)

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
