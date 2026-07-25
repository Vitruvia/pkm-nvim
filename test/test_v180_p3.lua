-- test/test_v180_p3.lua
-- Tests for v1.8.0 Phase 3: the tag picker's data and the batch confirmation.
--
-- The Telescope screens themselves are UI and stay hand-smoked (Telescope is not
-- on the runtimepath in headless), but everything they *display* is either pure
-- or read-only and is covered here: the counted tag rows, the "before → after"
-- row renderer, and the float front-end rendering a batch through opts.display.
--
-- Runs against a real headless Neovim instance on the disposable temp root
-- created by test/min_init.lua — never the live Notes tree.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v180_p3.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== tag picker data + batch confirmation (v1.8.0 Ph3) ==")

local pkm    = require('pkm')
local utils  = require('pkm.utils')
local yaml   = require('pkm.yaml')
local index  = require('pkm.index')
local tags   = require('pkm.tags')
local picker = require('pkm.picker')

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

-- Deliberate spellings: 'Zeta' and 'zeta' are the same tag written two ways,
-- and 0403 lists one of them twice.
local p1 = write_note('0401_note_one',   { 'alpha', 'Zeta' })
local p2 = write_note('0402_note_two',   { 'zeta' })
local p3 = write_note('0403_note_three', { 'Beta', 'beta' })
local p4 = write_note('0404_note_four',  {})
index.rebuild()

-- =============================================================================
-- tag_counts(): what the tag picker lists
-- =============================================================================

---@param rows table[]
---@param tag  string
---@return table|nil
local function row_for(rows, tag)
  for _, row in ipairs(rows) do
    if row.tag == tag then return row end
  end
  return nil
end

do
  local rows = tags.tag_counts()

  check("rows come back sorted by tag", (function()
    for i = 2, #rows do
      if rows[i - 1].tag >= rows[i].tag then return false end
    end
    return #rows > 0
  end)(), table.concat(vim.tbl_map(function(r) return r.tag end, rows), ', '))

  local zeta = row_for(rows, 'zeta')
  check("two spellings of one tag collapse into a single row",
    zeta ~= nil and row_for(rows, 'Zeta') == nil,
    zeta and 'found zeta' or 'no zeta row')
  check("and their notes are counted together",
    zeta ~= nil and zeta.count == 2 and #zeta.paths == 2,
    zeta and ('count=' .. zeta.count) or nil)

  local beta = row_for(rows, 'beta')
  check("a note listing the same tag twice counts once",
    beta ~= nil and beta.count == 1, beta and ('count=' .. beta.count) or 'no beta row')

  local alpha = row_for(rows, 'alpha')
  check("each row carries the paths behind the count",
    alpha ~= nil and #alpha.paths == 1
    and utils.normalize(alpha.paths[1]) == utils.normalize(p1),
    alpha and alpha.paths[1] or nil)

  check("an untagged note contributes no row",
    (function()
      for _, row in ipairs(rows) do
        for _, path in ipairs(row.paths) do
          if utils.normalize(path) == utils.normalize(p4) then return false end
        end
      end
      return true
    end)())
end

do
  local rows = tags.tag_counts({ p2, p3 })
  check("a path list restricts the rows to that selection",
    row_for(rows, 'alpha') == nil and row_for(rows, 'zeta') ~= nil
    and row_for(rows, 'beta') ~= nil,
    table.concat(vim.tbl_map(function(r) return r.tag end, rows), ', '))
  check("and the count is of selected notes only",
    row_for(rows, 'zeta').count == 1, tostring(row_for(rows, 'zeta').count))

  check("a selection with no tags yields no rows", #tags.tag_counts({ p4 }) == 0)
  check("an empty selection yields no rows",       #tags.tag_counts({}) == 0)
end

-- =============================================================================
-- format_change(): one row of the confirmation
-- =============================================================================

do
  local plan = tags.preview({ p1 }, { add = { 'gamma' } })
  local line = tags.format_change(plan[1])
  check("the row names the note by its stem",
    line:find('0401_note_one', 1, true) ~= nil, line)
  check("and shows before → after in stored order",
    line:find('alpha, Zeta  →  alpha, Zeta, gamma', 1, true) ~= nil, line)

  local emptied = tags.preview({ p2 }, { remove = { 'zeta' } })
  check("an emptied tag list reads as (none) on the right",
    tags.format_change(emptied[1]):find('zeta  →  (none)', 1, true) ~= nil,
    tags.format_change(emptied[1]))

  local seeded = tags.format_change({ path = p4, before = {}, after = { 'draft' } })
  check("and as (none) on the left when the note had no tags",
    seeded:find('(none)  →  draft', 1, true) ~= nil, seeded)
end

-- =============================================================================
-- picker.select(opts.display): the batch confirmation is a note picker
-- =============================================================================

--- Feed keys to the float and wait for the callback.
---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

do
  local ops  = { rename = { { from = 'zeta', to = 'omega' } } }
  local plan = tags.preview({ p1, p2, p3 }, ops)

  local paths, by_path = {}, {}
  for _, item in ipairs(plan) do
    paths[#paths + 1] = item.path
    by_path[item.path] = item
  end
  check("only the notes that would change reach the confirmation", #paths == 2,
    string.format('%d notes', #paths))

  local got
  picker.select(paths, {
    title   = 'PKMTags rename',
    hint    = 'apply to listed',
    display = function(path) return tags.format_change(by_path[path]) end,
  }, function(confirmed) got = confirmed end)

  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("rows render through opts.display, not the default filename+tags",
    shown:find('alpha, Zeta  →  alpha, omega', 1, true) ~= nil
    and shown:find('.md  [', 1, true) == nil, shown)
  check("the title states what <CR> will do",
    shown:find('<CR> apply to listed', 1, true) ~= nil, shown:sub(1, 90))

  feed('<CR>')
  vim.wait(1000, function() return got ~= nil end, 10)
  check("<CR> confirms every listed note", got ~= nil and #got == 2,
    got and ('#' .. #got) or 'callback never ran')

  -- Nothing has been written: the confirmation is read-only until apply().
  check("showing the confirmation writes nothing",
    #tags.preview({ p1 }, ops) == 1)
end

-- =============================================================================
-- select_tag(): the no-Telescope path is a plain choice
-- =============================================================================

do
  local chosen, prompted
  local orig_select = vim.ui.select
  vim.ui.select = function(items, opts, on_choice)
    prompted = opts.format_item(items[1])
    on_choice(items[1], 1)
  end

  picker.select_tag(tags.tag_counts(), { title = 'Browse by tag' },
    function(tag) chosen = tag end)
  vim.wait(1000, function() return chosen ~= nil end, 10)

  vim.ui.select = orig_select

  check("the fallback labels each tag with its note count",
    prompted ~= nil and prompted:find('alpha  (1 note)', 1, true) ~= nil, prompted)
  check("and hands back the plain tag string", chosen == 'alpha', tostring(chosen))

  local ran = false
  picker.select_tag({}, { title = 'Browse by tag' }, function() ran = true end)
  check("an empty tag list opens nothing", ran == false)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
