-- test/test_v1490_p1.lua
-- v1.49.0 — the sidebar container extracted onto pkm.panel (Area 3 Phase 3.2).
--
-- Two halves:
--   A. pkm.panel's new container API in isolation: spec.width (managed-width
--      side split), spec.on_open (per-panel decoration seam), refresh_all()
--      (rebuild every open tab from its own state), get_state() (live state
--      while open, nil while closed).
--   B. the views sidebar riding that container: it still opens as pkm-sidebar
--      with a fixed width and focus, reports through the same public API, and
--      its history / type-filter / marks keymaps still move the real state.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1490_p1.lua" -c "qa!"

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

local panel = require('pkm.panel')

-- =============================================================================
-- A. pkm.panel container API (width / on_open / refresh_all / get_state)
-- =============================================================================

print("== A. panel.create: managed width, on_open, refresh_all, get_state ==")

local on_open_fired = false
local content = { 'line one', 'line two' }
local p = panel.create({
  name          = 'test149',
  split_cmd     = 'noautocmd topleft vsplit',
  width         = 24,
  win_opts      = { winfixwidth = true },
  build_lines   = function(_) return content end,
  on_open       = function(_pstate) on_open_fired = true end,
  focus_on_open = true,
})

check("closed: get_state() is nil", p.get_state() == nil)
check("closed: is_open() is false", p.is_open() == false)

p.open()
check("on_open fired at open", on_open_fired)
check("is_open() true after open", p.is_open())
local st = p.get_state()
check("get_state() returns the live tab table", type(st) == 'table' and st.win ~= nil)
check("managed width applied", vim.api.nvim_win_get_width(p.get_win()) == 24,
  tostring(vim.api.nvim_win_get_width(p.get_win())))
check("winfixwidth is set on the panel window", vim.wo[p.get_win()].winfixwidth == true)
check("focus_on_open kept focus on the panel", vim.api.nvim_get_current_win() == p.get_win())
check("initial content rendered", vim.api.nvim_buf_get_lines(st.buf, 0, -1, false)[1] == 'line one')

content = { 'changed by refresh_all' }
p.refresh_all()
check("refresh_all() repopulated from build_lines",
  vim.api.nvim_buf_get_lines(st.buf, 0, -1, false)[1] == 'changed by refresh_all')

p.close()
check("closed again: get_state() nil", p.get_state() == nil)
check("closed again: is_open() false", not p.is_open())

-- =============================================================================
-- B. the views sidebar on the container
-- =============================================================================

print("\n== B. the views sidebar rides pkm.panel ==")

local pkm   = require('pkm')
local utils = require('pkm.utils')
local yaml  = require('pkm.yaml')
local index = require('pkm.index')
local views = require('pkm.views')

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

local function write_note(stem, note_tags)
  local lines = { '---' }
  vim.list_extend(lines, yaml.generate_yaml({ title = 'Note ' .. stem, tags = note_tags }))
  vim.list_extend(lines, { '---', '', 'Body of ' .. stem })
  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

write_note('1401_alpha_one', { 'alpha' })
write_note('1402_alpha_two', { 'alpha' })
write_note('1403_beta_one',  { 'beta' })
index.rebuild()
views.save('alpha', 'tag:alpha')
views.save('beta',  'tag:beta')

check("sidebar starts closed", views.is_sidebar_open() == false)
check("get_sidebar_win() nil while closed", views.get_sidebar_win() == nil)

views.open_sidebar('alpha')
check("opened on a view", views.is_sidebar_open())
local sw = views.get_sidebar_win()
check("get_sidebar_win() returns a valid window",
  sw ~= nil and vim.api.nvim_win_is_valid(sw))
check("container is the pkm-sidebar buffer",
  vim.bo[vim.api.nvim_win_get_buf(sw)].filetype == 'pkm-sidebar',
  vim.bo[vim.api.nvim_win_get_buf(sw)].filetype)
check("winfixwidth is set (managed-width side split)", vim.wo[sw].winfixwidth == true)
check("width matches config.sidebar_width",
  vim.api.nvim_win_get_width(sw) == (pkm.config.sidebar_width or 40),
  tostring(vim.api.nvim_win_get_width(sw)))
check("focus is on the sidebar after open", vim.api.nvim_get_current_win() == sw)
check("get_last_view() reports the open detail view", views.get_last_view() == 'alpha')

-- History: switching to another view while open pushes the current onto the
-- stack; <BS> pops back to it.
vim.api.nvim_set_current_win(sw)
views.open_sidebar('beta')
check("switching view lands on the new view", views.get_last_view() == 'beta')
feed('<BS>')
check("<BS> pops history back to the previous view", views.get_last_view() == 'alpha',
  tostring(views.get_last_view()))

-- Type filter: <C-t> cycles the note-type filter in detail mode. There is no
-- public getter for the private field, so we assert the gesture drives the
-- migrated state without throwing and leaves the sidebar rendered (the visual
-- filter label is left to the manual smoke).
feed('<C-t>')
check("<C-t> kept the sidebar open in detail mode", views.is_sidebar_open())
check("detail still renders after a type-filter cycle",
  #vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sw), 0, -1, false) > 0)

-- refresh_sidebar_if_open() must not throw and must keep the sidebar open.
views.refresh_sidebar_if_open()
check("refresh_sidebar_if_open kept the sidebar open", views.is_sidebar_open())

-- Close via the sidebar's own q (two non-float windows here, so it closes the
-- sidebar rather than quitting).
vim.api.nvim_set_current_win(sw)
feed('q')
check("q closed the sidebar", not views.is_sidebar_open())
check("get_sidebar_win() nil again", views.get_sidebar_win() == nil)

-- No-arg toggle from closed opens overview; toggling again closes.
views.open_sidebar()
check("no-arg open_sidebar opened overview", views.is_sidebar_open())
check("overview has no active detail view", views.get_last_view() ~= 'alpha' and views.get_last_view() ~= 'beta')
views.open_sidebar()
check("no-arg open_sidebar toggled it closed", not views.is_sidebar_open())

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
