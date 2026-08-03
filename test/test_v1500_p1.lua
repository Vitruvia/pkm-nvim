-- test/test_v1500_p1.lua
-- v1.50.0 — near-patch from the author's notes:
--   A. utils.winbar_label — the "title · filename(with number)" panel winbar text
--   B. no double-build: opening the sidebar builds the overview once, not twice
--   C. views.focus_sidebar — <leader>s toggles focus in/out, storing the source win
--   D. nav panel header carries the current vault indicator
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1500_p1.lua" -c "qa!"

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

-- =============================================================================
-- A. utils.winbar_label (pure)
-- =============================================================================

print("== A. utils.winbar_label ==")

check("title · filename, number kept",
  utils.winbar_label({ title = 'My Note' }, '/x/0282_note_my-note.md')
    == ' My Note  ·  0282_note_my-note',
  utils.winbar_label({ title = 'My Note' }, '/x/0282_note_my-note.md'))
check("filename only when no entry/title",
  utils.winbar_label(nil, '/x/0282_note_my-note.md') == ' 0282_note_my-note')
check("filename only when title equals the stem (no redundant duplication)",
  utils.winbar_label({ title = '0282_note_my-note' }, '/x/0282_note_my-note.md')
    == ' 0282_note_my-note')
check("% is doubled for the winbar mini-language",
  utils.winbar_label({ title = '50% done' }, '/x/0001_note_x.md')
    == ' 50%% done  ·  0001_note_x',
  utils.winbar_label({ title = '50% done' }, '/x/0001_note_x.md'))

-- =============================================================================
-- Fixture: a couple of views + notes
-- =============================================================================

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')
local function write_note(stem, tags)
  local lines = { '---' }
  vim.list_extend(lines, yaml.generate_yaml({ title = 'Note ' .. stem, tags = tags }))
  vim.list_extend(lines, { '---', '', 'Body of ' .. stem })
  vim.fn.writefile(lines, utils.join(notes_dir, stem .. '.md'))
end
write_note('1501_alpha_one', { 'alpha' })
write_note('1502_alpha_two', { 'alpha' })
index.rebuild()
views.save('alpha', 'tag:alpha')
views.save('beta',  'tag:beta')

-- =============================================================================
-- B. no double-build on open
-- =============================================================================

print("\n== B. opening the sidebar builds the overview once (no double-build) ==")

if views.is_sidebar_open() then views.open_sidebar() end
check("sidebar closed before the build-count probe", not views.is_sidebar_open())

local orig_count_many = views.count_many
local cm_calls = 0
views.count_many = function(...) cm_calls = cm_calls + 1; return orig_count_many(...) end
views.open_sidebar()             -- fresh overview open
views.count_many = orig_count_many
check("count_many ran exactly once during open", cm_calls == 1, tostring(cm_calls))
check("the overview still opened", views.is_sidebar_open())
views.open_sidebar()             -- toggle it closed again
check("sidebar closed after the probe", not views.is_sidebar_open())

-- =============================================================================
-- C. focus_sidebar toggle
-- =============================================================================

print("\n== C. views.focus_sidebar toggles focus and stores the source window ==")

if views.is_sidebar_open() then views.open_sidebar() end
check("sidebar closed before the focus test", not views.is_sidebar_open())

local source_win = vim.api.nvim_get_current_win()
views.focus_sidebar()            -- closed -> opens (overview), focus lands on it
check("focus_sidebar opens the sidebar when closed", views.is_sidebar_open())
local sb = views.get_sidebar_win()
check("focus is on the sidebar", vim.api.nvim_get_current_win() == sb)

views.focus_sidebar()            -- inside -> jump back to source
check("focus_sidebar from inside returns to the source window",
  vim.api.nvim_get_current_win() == source_win,
  tostring(vim.api.nvim_get_current_win()) .. ' vs ' .. tostring(source_win))

views.focus_sidebar()            -- outside -> record + focus again
check("focus_sidebar from outside re-focuses the sidebar",
  vim.api.nvim_get_current_win() == sb)

views.open_sidebar()             -- close (we are inside; no-arg toggles closed)
check("sidebar closed after the focus test", not views.is_sidebar_open())

-- =============================================================================
-- D. nav header carries the vault indicator
-- =============================================================================

print("\n== D. nav panel header shows the current vault ==")

local nav   = require('pkm.nav')
local vault = require('pkm.vault')
local orig_indicator = vault.indicator
vault.indicator = function() return '00 · Test' end

local nb = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(nb, 0, -1, false, { '# Heading', 'body' })
vim.api.nvim_buf_set_name(nb, '/tmp/navnote.md')
vim.bo[nb].filetype = 'markdown'
local nlines = nav._headings_of(nb, '')
check("nav header shows the vault indicator", nlines[1]:find('00 · Test', 1, true) ~= nil, nlines[1])
check("nav header still shows the filename", nlines[1]:find('navnote.md', 1, true) ~= nil, nlines[1])

vault.indicator = function() return '' end
local nlines2 = nav._headings_of(nb, '')
check("no vault indicator → header is just the filename (no dangling separator)",
  nlines2[1] == '≡ navnote.md', nlines2[1])
vault.indicator = orig_indicator

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
