-- test/test_v1520_p1.lua
-- v1.52.0 — Area 3 Phase 3.3b: sidebar autoswitch. With autoswitch on, the open
-- sidebar follows focus — nav when a markdown window is focused, views when no
-- window holds a markdown file — but only on a CONTEXT TRANSITION, so a manual
-- cycle sticks until the context actually changes. Toggled by :PKMPanel
-- autoswitch / views.set_autoswitch. Driven by calling views.autoswitch_tick()
-- with the window focus arranged, which is exactly what nav's tracker does.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1520_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm   = require('pkm')
local utils = require('pkm.utils')
local yaml  = require('pkm.yaml')
local index = require('pkm.index')
local views = require('pkm.views')

-- Fixture: a view (so the views provider has something to show).
local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')
local lines = { '---' }
vim.list_extend(lines, yaml.generate_yaml({ title = 'Note a', tags = { 'alpha' } }))
vim.list_extend(lines, { '---', '', 'body' })
vim.fn.writefile(lines, utils.join(notes_dir, '1521_alpha_one.md'))
index.rebuild()
views.save('alpha', 'tag:alpha')

-- A main window that we swap between a markdown buffer and a plain-text buffer.
vim.cmd('enew')
local main   = vim.api.nvim_get_current_win()
local txtbuf = vim.api.nvim_get_current_buf()
vim.bo[txtbuf].filetype = 'text'

local notef = vim.fn.tempname() .. '/src.md'
local mdbuf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(mdbuf, 0, -1, false, { '# Top', 'x', '## Sub' })
vim.api.nvim_buf_set_name(mdbuf, notef)
vim.bo[mdbuf].filetype = 'markdown'

local function focus_markdown() vim.api.nvim_win_set_buf(main, mdbuf); vim.api.nvim_set_current_win(main) end
local function focus_text()     vim.api.nvim_win_set_buf(main, txtbuf); vim.api.nvim_set_current_win(main) end

views.set_autoswitch('on')
local sp = views.sidebar_provider(); if sp then views.show_sidebar_provider(sp) end   -- ensure closed

print("== opening context + auto-flip to nav ==")
focus_text()
views.open_sidebar()   -- no markdown focused → views
check("opens on views when no markdown is focused", views.sidebar_provider() == 'views',
  tostring(views.sidebar_provider()))

focus_markdown()
views.autoswitch_tick()
check("focusing a markdown window flips the sidebar to nav",
  views.sidebar_provider() == 'nav', tostring(views.sidebar_provider()))
check("nav content is the focused note's headings", (function()
  local sw = views.get_sidebar_win()
  local joined = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sw), 0, -1, false), '\n')
  return joined:find('Top', 1, true) ~= nil
end)())

print("\n== fall back to views when no markdown window remains ==")
focus_text()
views.autoswitch_tick()
check("no markdown left → back to views", views.sidebar_provider() == 'views',
  tostring(views.sidebar_provider()))

print("\n== focusing a non-md file switches to views even if a markdown window remains ==")
focus_markdown(); views.autoswitch_tick()          -- nav (main is markdown)
vim.cmd('vsplit')                                   -- a second window, still markdown
local w2 = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(main, txtbuf)              -- main now non-markdown; w2 stays markdown
vim.api.nvim_set_current_win(main)
views.autoswitch_tick()
check("non-md focus → views though a markdown window is still open",
  views.sidebar_provider() == 'views', tostring(views.sidebar_provider()))
vim.api.nvim_win_close(w2, true)

print("\n== a manual cycle is a transient peek; refocusing reverts it (live) ==")
focus_markdown()
views.autoswitch_tick()
check("markdown again → nav", views.sidebar_provider() == 'nav')
views.cycle_sidebar_provider()          -- a manual peek: nav -> views
check("manual cycle to views", views.sidebar_provider() == 'views')
focus_markdown()                        -- re-focus the markdown editing window
views.autoswitch_tick()
check("re-focusing the markdown window reverts to nav (autoswitch keeps working)",
  views.sidebar_provider() == 'nav', tostring(views.sidebar_provider()))

print("\n== toggle off pins the sidebar ==")
check("set_autoswitch('off') returns false", views.set_autoswitch('off') == false)
check("autoswitch_enabled() is false", views.autoswitch_enabled() == false)
focus_text()
views.autoswitch_tick()
check("with autoswitch off, no flip on context change (stays nav)",
  views.sidebar_provider() == 'nav', tostring(views.sidebar_provider()))
check("set_autoswitch('on') returns true", views.set_autoswitch('on') == true)

print("\n== focus_sidebar opens context-appropriately ==")
local sp2 = views.sidebar_provider(); if sp2 then views.show_sidebar_provider(sp2) end
check("closed before the focus_sidebar test", not views.is_sidebar_open())
focus_markdown()
views.focus_sidebar()
check("focus_sidebar from a markdown window opens on nav", views.sidebar_provider() == 'nav',
  tostring(views.sidebar_provider()))

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
