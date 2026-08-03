-- test/test_v1510_p1.lua
-- v1.51.0 — Area 3 Phase 3.3a: one sidebar container, two content providers
-- (views + nav), switched IN PLACE. The crux is that switching provider swaps
-- the buffer-local keymaps (so nav's <CR>/<CR>/r never fight views', and views'
-- mark/type keys are gone under nav) while the common keys survive. This drives
-- that directly through the buffer's keymap table and the statusline.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1510_p1.lua" -c "qa!"

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

-- Fixture: one view + notes, and a markdown buffer to be the nav source.
local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')
local function write_note(stem, tags)
  local lines = { '---' }
  vim.list_extend(lines, yaml.generate_yaml({ title = 'Note ' .. stem, tags = tags }))
  vim.list_extend(lines, { '---', '', 'Body of ' .. stem })
  vim.fn.writefile(lines, utils.join(notes_dir, stem .. '.md'))
end
write_note('1511_alpha_one', { 'alpha' })
index.rebuild()
views.save('alpha', 'tag:alpha')

local notef = vim.fn.tempname() .. '/src.md'
vim.fn.mkdir(vim.fn.fnamemodify(notef, ':h'), 'p')
vim.fn.writefile({ '# Top', 'x', '## Sub', 'y' }, notef)
vim.cmd('edit ' .. vim.fn.fnameescape(notef))
vim.bo.filetype = 'markdown'

--- Does buffer `buf` have a normal-mode mapping for `lhs`? (plain-letter lhs, to
--- sidestep termcode normalisation in the keymap table).
local function has_map(buf, lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if m.lhs == lhs then return true end
  end
  return false
end

local function statusline(win)
  return vim.api.nvim_get_option_value('statusline', { win = win })
end

-- Start closed.
local shown = views.sidebar_provider()
if shown then views.show_sidebar_provider(shown) end
check("sidebar starts closed", not views.is_sidebar_open())

print("== views provider: its keys are live, nav-only keys are not ==")
views.show_sidebar_provider('views')
check("open on views", views.sidebar_provider() == 'views')
local sw  = views.get_sidebar_win()
local buf = vim.api.nvim_win_get_buf(sw)
check("views key 'T' (labels) is mapped",  has_map(buf, 'T'))
check("views key 'N' (new here) is mapped", has_map(buf, 'N'))
check("views key 'b' (back) is mapped",     has_map(buf, 'b'))
check("nav-only key 'c' (clear) is NOT mapped under views", not has_map(buf, 'c'))
check("common 'q' (close) is mapped",       has_map(buf, 'q'))
check("statusline is the views hint", statusline(sw):find('PKM Views', 1, true) ~= nil, statusline(sw))

print("\n== switch to nav: views-only keys torn down, nav keys applied ==")
views.set_sidebar_provider('nav')
check("now on nav", views.sidebar_provider() == 'nav')
check("same window/buffer — switched IN PLACE",
  views.get_sidebar_win() == sw and vim.api.nvim_win_get_buf(sw) == buf)
check("views 'T' is torn down under nav",  not has_map(buf, 'T'))
check("views 'N' is torn down under nav",  not has_map(buf, 'N'))
check("views 'b' is torn down under nav",  not has_map(buf, 'b'))
check("common 'q' survived the swap",      has_map(buf, 'q'))
check("shared 'r' is still mapped",        has_map(buf, 'r'))
check("statusline is now the nav hint", statusline(sw):find('PKM Nav', 1, true) ~= nil, statusline(sw))
local navlines = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
check("nav content: the source note's headings render", navlines:find('Top', 1, true) ~= nil, navlines)

print("\n== cycle back to views: views keys restored, nav-only key gone ==")
views.cycle_sidebar_provider()
check("cycled to views", views.sidebar_provider() == 'views')
check("views 'T' restored", has_map(buf, 'T'))
check("statusline back to views", statusline(sw):find('PKM Views', 1, true) ~= nil, statusline(sw))

print("\n== :PKMPanel nav toggles the nav provider closed when already on it ==")
views.show_sidebar_provider('nav')          -- views -> nav
check("switched to nav", views.sidebar_provider() == 'nav')
views.show_sidebar_provider('nav')          -- nav -> closed
check("showing the active provider again closed the sidebar", not views.is_sidebar_open())

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
