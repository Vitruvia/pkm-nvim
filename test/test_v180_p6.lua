-- test/test_v180_p6.lua
-- Tests for v1.8.0 Phase 6: marking notes in the view surfaces.
--
-- The marking rule is pure and asserted directly; the sidebar is then driven
-- for real — opened on a disposable view, marked through its own <Tab> keymap,
-- and inspected through its buffer, which is the only way to prove that the
-- marker reaches the screen and survives a refresh.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v180_p6.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== marking notes in the view surfaces (v1.8.0 Ph6) ==")

local pkm   = require('pkm')
local utils = require('pkm.utils')
local yaml  = require('pkm.yaml')
local index = require('pkm.index')
local views = require('pkm.views')

-- =============================================================================
-- The marking rule, pure
-- =============================================================================

do
  local marked = {}

  check("toggling an unmarked key marks it",
    views.toggle_mark(marked, 'a') == true and marked.a == true)
  check("toggling it again clears it",
    views.toggle_mark(marked, 'a') == false and marked.a == nil)
  check("a nil key is ignored", views.toggle_mark(marked, nil) == false)
  check("a nil set is ignored", views.toggle_mark(nil, 'a') == false)
end

do
  local ordered = { 'a', 'b', 'c' }

  check("with nothing marked, everything listed is acted on",
    table.concat(views.marked_in_order({}, ordered), ',') == 'a,b,c')

  check("marks are returned in display order, not marking order",
    table.concat(views.marked_in_order({ c = true, a = true }, ordered), ',') == 'a,c')

  check("a mark for something no longer listed is dropped",
    table.concat(views.marked_in_order({ z = true, b = true }, ordered), ',') == 'b')

  check("a mark set holding only stale keys falls back to everything listed",
    table.concat(views.marked_in_order({ z = true }, ordered), ',') == 'a,b,c')

  check("an empty list stays empty", #views.marked_in_order({ a = true }, {}) == 0)
  check("a nil mark set is the whole list",
    table.concat(views.marked_in_order(nil, ordered), ',') == 'a,b,c')
end

-- =============================================================================
-- The sidebar, driven for real
-- =============================================================================

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

---@param stem string
---@param note_tags string[]
---@return string path
local function write_note(stem, note_tags)
  local fm_lines = yaml.generate_yaml({ title = 'Note ' .. stem, tags = note_tags })
  local lines = { '---' }
  vim.list_extend(lines, fm_lines)
  vim.list_extend(lines, { '---', '', 'Body of ' .. stem })
  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

write_note('0701_note_one',   { 'ph6' })
write_note('0702_note_two',   { 'ph6' })
write_note('0703_note_three', { 'ph6' })
write_note('0704_note_other', { 'elsewhere' })
index.rebuild()

views.save('ph6', 'tag:ph6')
views.save('ph6b', 'tag:elsewhere')

--- Feed keys to the sidebar window and let its keymap run.
---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

---@return string[]
local function sidebar_lines()
  local win = views.get_sidebar_win()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

---@return integer  count of rows rendered as marked
local function marked_rows()
  local n = 0
  for _, line in ipairs(sidebar_lines()) do
    if line:sub(1, #'▸') == '▸' then n = n + 1 end
  end
  return n
end

do
  views.open_sidebar('ph6')
  check("the sidebar opened on the view", views.is_sidebar_open())

  local win = views.get_sidebar_win()
  vim.api.nvim_set_current_win(win)

  local before = sidebar_lines()
  check("it lists the view's three notes", (function()
    local n = 0
    for _, line in ipairs(before) do
      if line:find('note_', 1, true) then n = n + 1 end
    end
    return n == 3
  end)(), table.concat(before, ' | '))
  check("nothing starts marked", marked_rows() == 0)

  -- The cursor lands on the first note row when the view opens.
  feed('<Tab>')
  check("<Tab> marks the note under the cursor", marked_rows() == 1,
    table.concat(sidebar_lines(), ' | '))
  check("and the row keeps its column alignment", (function()
    for _, line in ipairs(sidebar_lines()) do
      if line:sub(1, #'▸') == '▸' then
        return #line == #before[3] or line:sub(#'▸' + 1, #'▸' + 1) == ' '
      end
    end
    return false
  end)())

  feed('<Tab>')
  check("<Tab> on the next row marks a second note", marked_rows() == 2)

  views.refresh_sidebar_if_open()
  check("a refresh preserves the marks", marked_rows() == 2)

  -- The cursor now sits on the third note, which no <Tab> has touched: the
  -- gesture toggles whatever is under it, so this marks and steps *up*.
  feed('<S-Tab>')
  check("<S-Tab> toggles the row under the cursor and steps up",
    marked_rows() == 3, table.concat(sidebar_lines(), ' | '))

  -- Stepping up lands on the second note, which is marked — so this clears it.
  feed('<S-Tab>')
  check("toggling a marked row clears it", marked_rows() == 2,
    table.concat(sidebar_lines(), ' | '))
end

do
  -- Switching to another view starts clean: its notes were never marked.
  views.open_sidebar('ph6b')
  check("entering another view clears the marks", marked_rows() == 0,
    table.concat(sidebar_lines(), ' | '))
end

do
  -- <C-a> with nothing marked offers every note listed; the action menu is a
  -- vim.ui.select, so stubbing it reveals what was collected.
  views.open_sidebar('ph6')
  vim.api.nvim_set_current_win(views.get_sidebar_win())

  local orig = vim.ui.select
  local prompt
  vim.ui.select = function(_, opts) prompt = opts.prompt end

  feed('<C-a>')
  vim.wait(500, function() return prompt ~= nil end, 10)
  check("<C-a> with no marks acts on every note listed",
    prompt ~= nil and prompt:find('3 notes', 1, true) ~= nil, tostring(prompt))

  prompt = nil
  feed('<Tab>')
  feed('<C-a>')
  vim.wait(500, function() return prompt ~= nil end, 10)
  check("and with one marked, on that one alone",
    prompt ~= nil and prompt:find('1 note', 1, true) ~= nil, tostring(prompt))

  vim.ui.select = orig
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
