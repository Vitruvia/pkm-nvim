-- test/test_sidebar_reopen.lua
-- Bug (found in v1.71.0 smoke, notes 0289/0293): with the sidebar AND the buffer
-- panel both open, `:quit`-ing the last note window left a tabpage of panels
-- only — no editing window — because panel.ensure_main_window counted the OTHER
-- panel as a "main window" and skipped recreating one. The sidebar then
-- collapsed to a full-width strip, note-opens landed in the wrong place, and the
-- sidebar's nav provider dead-ended with "the note window is gone".
--
-- This proves the two fixes:
--   1. panel.ensure_main_window recreates a real editing window when only PKM
--      panels remain, restoring a sidebar-left / bufpanel-bottom layout.
--   2. nav.live_source_win revives the note in an editing window when its own
--      window was closed but the buffer still lives, instead of dead-ending.
--
-- Run: nvim --headless -u test/min_init.lua -c "luafile test/test_sidebar_reopen.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end

local utils = require('pkm.utils')
local views = require('pkm.views')
local ui    = require('pkm.ui')
local nav   = require('pkm.nav')

local function reset()
  if views.is_sidebar_open() then views.open_sidebar() end
  if ui.is_bufpanel_open() then ui.toggle_bufpanel() end
  -- Land on a normal (non-winfixbuf) window before collapsing to one buffer,
  -- so `enew` is never attempted from a panel window.
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not vim.wo[w].winfixbuf and vim.api.nvim_win_get_config(w).relative == '' then
      vim.api.nvim_set_current_win(w); break
    end
  end
  vim.cmd('silent! only')
  vim.cmd('enew')
end

-- ===========================================================================
print("== ensure_main_window recreates an editing window when only panels remain ==")
reset()
vim.cmd('enew')
local note_buf = vim.api.nvim_get_current_buf()
vim.bo[note_buf].filetype = 'markdown'
local note_win = vim.api.nvim_get_current_win()

if not views.is_sidebar_open() then views.open_sidebar() end
if not ui.is_bufpanel_open() then ui.toggle_bufpanel() end
check("two panels + a note window are open",
  views.is_sidebar_open() and ui.is_bufpanel_open() and #utils.editing_wins() == 1,
  "editing_wins=" .. #utils.editing_wins())

-- :quit the sole editing window; both panels' WinClosed nets are scheduled.
vim.api.nvim_set_current_win(note_win)
pcall(vim.cmd, 'quit')
vim.wait(80)

check("an editing window was recreated (not stranded on panels)",
  #utils.editing_wins() >= 1, "editing_wins=" .. #utils.editing_wins())
check("the sidebar is still open", views.is_sidebar_open())
check("the buffer panel is still open", ui.is_bufpanel_open())

-- The sidebar must remain a left column at its managed width, not a full-width
-- strip. Find the sidebar window and assert its width is the configured one.
local sidebar_win
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'pkm-sidebar' then sidebar_win = w end
end
local want_w = require('pkm').config.sidebar_width or 40
check("sidebar kept its managed width (left column, not a strip)",
  sidebar_win ~= nil and vim.api.nvim_win_get_width(sidebar_win) == want_w,
  sidebar_win and ("width=" .. vim.api.nvim_win_get_width(sidebar_win) .. " want=" .. want_w) or "no sidebar")

-- ===========================================================================
print("\n== nav.live_source_win revives a closed note window from its buffer ==")
reset()
-- A markdown buffer with headings as the nav source.
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# Title', '', '## Alpha', 'x', '## Beta', 'y' })
vim.bo[buf].filetype = 'markdown'
local win = vim.api.nvim_get_current_win()
nav.capture_current()   -- remember this window/buffer as the source

-- Give nav somewhere to revive into, then close the source window.
vim.cmd('noautocmd rightbelow vsplit')  -- a second editing window
vim.cmd('enew')                          -- non-markdown, so it's a plain target
local other = vim.api.nvim_get_current_win()
vim.api.nvim_win_close(win, true)        -- the note's own window is gone now
check("source window is closed but its buffer still lives",
  not vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf))

vim.api.nvim_set_current_win(other)
local revived = nav._live_source_win()
check("live_source_win returned a valid window", revived ~= nil and vim.api.nvim_win_is_valid(revived))
check("the revived window shows the note buffer",
  revived ~= nil and vim.api.nvim_win_get_buf(revived) == buf,
  revived and ("shows buf " .. vim.api.nvim_win_get_buf(revived) .. ", want " .. buf) or "nil")

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
