-- test/test_v1530_p1.lua
-- v1.53.0 — Area 3 Phase 3.5a: content-consistent `/` from the sidebar.
--   A. pkm.ui.pick_list — the vim.ui.select list-picker fallback.
--   B. the views provider's `/` in OVERVIEW opens a picker of VIEW NAMES (not
--      the all-notes browse); choosing a view switches THIS sidebar to it —
--      the pop-up was launched from the sidebar, so it drives the sidebar back
--      (the origin rule). Driven through the real `/` keymap via feedkeys, with
--      vim.ui.select stubbed (no Telescope in the headless run).
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1530_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local pkm   = require('pkm')
local utils = require('pkm.utils')
local yaml  = require('pkm.yaml')
local index = require('pkm.index')
local views = require('pkm.views')

print("== A. pkm.ui.pick_list ==")
do
  local orig = vim.ui.select
  local got
  vim.ui.select = function(items, _opts, cb) cb(items[2]) end   -- choose the 2nd item
  require('pkm.ui').pick_list('T', { { display = 'a', value = 'A' }, { display = 'b', value = 'B' } },
    function(v) got = v end)
  check("pick_list passes the chosen item's value to on_select", got == 'B', tostring(got))

  got = nil
  vim.ui.select = function(_items, _opts, cb) cb(nil) end        -- cancelled
  require('pkm.ui').pick_list('T', { { display = 'a', value = 'A' } }, function(v) got = v end)
  check("a cancelled pick calls nothing", got == nil)
  vim.ui.select = orig
end

-- Fixture: two views + notes.
local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')
local function write_note(stem, tags)
  local lines = { '---' }
  vim.list_extend(lines, yaml.generate_yaml({ title = 'Note ' .. stem, tags = tags }))
  vim.list_extend(lines, { '---', '', 'body' })
  vim.fn.writefile(lines, utils.join(notes_dir, stem .. '.md'))
end
write_note('1531_alpha_one', { 'alpha' })
write_note('1532_beta_one',  { 'beta' })
index.rebuild()
views.save('alpha', 'tag:alpha')
views.save('beta',  'tag:beta')

print("\n== B. overview '/' searches views and switches the sidebar to the pick ==")
local shown = views.sidebar_provider(); if shown then views.show_sidebar_provider(shown) end
views.open_sidebar()                 -- open on views overview
check("sidebar open on views overview", views.sidebar_provider() == 'views' and views.get_last_view() == nil)

local orig = vim.ui.select
local offered = nil
vim.ui.select = function(items, _opts, cb)
  offered = {}
  for _, it in ipairs(items) do offered[#offered + 1] = it.value end
  for _, it in ipairs(items) do if it.value == 'beta' then cb(it); return end end
  cb(nil)
end
vim.api.nvim_set_current_win(views.get_sidebar_win())
feed('/')
vim.wait(500, function() return views.get_last_view() == 'beta' end, 10)
vim.ui.select = orig

check("the picker offered the view names (not notes)",
  offered ~= nil and vim.tbl_contains(offered, 'alpha') and vim.tbl_contains(offered, 'beta'),
  offered and table.concat(offered, ',') or 'nil')
check("choosing a view switched the sidebar to it (detail on 'beta')",
  views.sidebar_provider() == 'views' and views.get_last_view() == 'beta',
  tostring(views.get_last_view()))

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
