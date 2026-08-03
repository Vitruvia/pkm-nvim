-- test/test_v1560_p1.lua
-- v1.56.0 — Area 3 Phase 3.5b (slice 2): the cyclable pop-up container.
--   A. pkm.popup._next_provider — the browse → views → nav → browse cycle order.
--   B. pkm.popup.open('nav')  dispatches to the nav headings pop-up (jump).
--   C. pkm.popup.open('views') dispatches to the standalone views pop-up (offers
--      view names; STANDALONE — selecting activates the view, does not drive the
--      sidebar). The <C-l> cycle key itself is Telescope-only and smoke-tested.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1560_p1.lua" -c "qa!"

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
local popup = require('pkm.popup')

print("== A. cycle order browse → views → nav → browse ==")
check("browse → views", popup._next_provider('browse') == 'views')
check("views → nav",    popup._next_provider('views') == 'nav')
check("nav → browse",   popup._next_provider('nav') == 'browse')

-- Fixture: a view + a markdown source note.
local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')
local lines = { '---' }
vim.list_extend(lines, yaml.generate_yaml({ title = 'Note a', tags = { 'alpha' } }))
vim.list_extend(lines, { '---', '', 'body' })
vim.fn.writefile(lines, utils.join(notes_dir, '1561_alpha_one.md'))
index.rebuild()
require('pkm.views').save('alpha', 'tag:alpha')

local notef = vim.fn.tempname() .. '/src.md'
vim.fn.mkdir(vim.fn.fnamemodify(notef, ':h'), 'p')
vim.fn.writefile({ '# Top', 'x', '## Sub', 'y', '### Deep' }, notef)
vim.cmd('edit ' .. vim.fn.fnameescape(notef))
vim.bo.filetype = 'markdown'

local function win_for(sub)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)):find(sub, 1, true) then return w end
  end
end
local src_win = win_for('src.md')

print("\n== B. popup.open('nav') → headings pop-up (jump) ==")
vim.api.nvim_set_current_win(src_win)   -- so nav adopts this window as its source
local orig = vim.ui.select
vim.ui.select = function(items, _opts, cb)
  for _, it in ipairs(items) do if it.value == 3 then cb(it); return end end   -- '## Sub'
  cb(nil)
end
popup.open('nav')
vim.ui.select = orig
check("popup.open('nav') opened the headings pop-up and jumped the source to line 3",
  vim.api.nvim_win_get_cursor(src_win)[1] == 3,
  tostring(vim.api.nvim_win_get_cursor(src_win)[1]))

print("\n== C. popup.open('views') → standalone views pop-up (offers names) ==")
local offered
vim.ui.select = function(items, _opts, cb)
  offered = {}
  for _, it in ipairs(items) do offered[#offered + 1] = it.value end
  cb(nil)   -- cancel: standalone select would activate the view (its own picker)
end
popup.open('views')
vim.ui.select = orig
check("popup.open('views') offered the view names",
  offered ~= nil and vim.tbl_contains(offered, 'alpha'),
  offered and table.concat(offered, ',') or 'nil')

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
