-- test/test_v1840_p1.lua
-- Tests for v1.84.0: per-note tagging goes through the shared tag picker.
--
-- Bare `:PKMTag add` / `:PKMTag remove` (and <leader>ta / <leader>tr) used to
-- open a built-in split list with no Telescope variant and no way to create a
-- tag. They now open `picker.select_tag`: every vault tag ranked for the note,
-- a case- and accent-insensitive filter, and "← new tag" for text that is not a
-- tag yet. The Telescope screen is not reachable headless; the pure filter it
-- runs on is asserted directly, and the command flow runs through the
-- no-Telescope fallback (vim.ui.select / vim.ui.input stubbed).
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1840_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== per-note tag picker (v1.84.0) ==")

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

---@param rows table[]
---@return string[]
local function tag_order(rows)
  local out = {}
  for _, row in ipairs(rows) do out[#out + 1] = row.tag end
  return out
end

---@param rows table[]
---@param tag  string
---@return table|nil
local function row_for(rows, tag)
  for _, row in ipairs(rows) do
    if row.tag == tag then return row end
  end
  return nil
end

--- The current buffer's frontmatter tags, as written in it.
---@return string[]
local function buffer_tags()
  local fm = yaml.parse_frontmatter(vim.api.nvim_buf_get_lines(0, 0, -1, false))
  local out = {}
  for _, t in ipairs((fm and fm.tags) or {}) do out[#out + 1] = tostring(t) end
  return out
end

-- =============================================================================
-- utils.fold(): moved out of pkm.api, shared with the picker
-- =============================================================================

check("fold lower-cases and strips accents",
  utils.fold('Orçamentária') == 'orcamentaria', utils.fold('Orçamentária'))
check("fold folds upper-case accents too (string.lower is ASCII-only)",
  utils.fold('FÍSICA ÓPTICA') == 'fisica optica', utils.fold('FÍSICA ÓPTICA'))
check("fold tolerates nil", utils.fold(nil) == '')

-- =============================================================================
-- picker._tag_rows_matching(): the filter the Telescope screen runs on
-- =============================================================================

do
  local rows = {
    { tag = 'física',   count = 3, paths = {} },
    { tag = 'química',  count = 2, paths = {} },
    { tag = 'fisiologia', count = 1, paths = {} },
  }
  local match = picker._tag_rows_matching

  check("an empty prompt lists every row, in the caller's order",
    table.concat(tag_order(match(rows, '', true)), ',') == 'física,química,fisiologia')

  local r = match(rows, 'fisica', true)
  check("typing without the accent still lists the accented tag",
    row_for(r, 'física') ~= nil, table.concat(tag_order(r), ','))
  check("and offers what was typed as a new tag, first",
    r[1].is_new == true and r[1].tag == 'fisica', table.concat(tag_order(r), ','))

  r = match(rows, '  Física ', true)
  check("typing an existing tag (any case, padded) offers no new row",
    #r == 1 and r[1].tag == 'física' and not r[1].is_new, table.concat(tag_order(r), ','))

  r = match(rows, 'fis', true)
  check("a partial term lists every tag containing it",
    row_for(r, 'física') and row_for(r, 'fisiologia') and not row_for(r, 'química'),
    table.concat(tag_order(r), ','))

  r = match(rows, 'nova', false)
  check("without allow_new, no match means nothing listed", #r == 0)
end

-- =============================================================================
-- tags.suggest_tags_for(): ranking for ONE note, from its own tag list
-- =============================================================================

write_note('0701_note_one',   { 'physics', 'quantum' })
write_note('0702_note_two',   { 'physics', 'quantum' })
write_note('0703_note_three', { 'cooking' })
write_note('0704_note_four',  { 'cooking' })
write_note('0705_note_five',  { 'cooking' })
local target = write_note('0706_note_target', { 'physics' })
write_note('0707_note_budget', { 'orçamentária' })   -- for the api.find check
index.rebuild()

do
  local rows = tags.suggest_tags_for({ 'Physics' })
  check("a tag that keeps company with the note's tags ranks first",
    rows[1].tag == 'quantum', table.concat(tag_order(rows), ','))
  check("an unrelated tag comes after it, despite more use",
    rows[2].tag == 'cooking', table.concat(tag_order(rows), ','))
  local physics = row_for(rows, 'physics')
  check("the note's own tag goes last, labelled for one note",
    rows[#rows].tag == 'physics' and physics.note == 'already on this note',
    tostring(physics and physics.note))

  local bare = tags.suggest_tags_for({})
  check("a note with no tags gets the plain usage order",
    bare[1].tag == 'cooking', table.concat(tag_order(bare), ','))
end

-- =============================================================================
-- :PKMTag add / remove, bare: the picker, then a buffer-only write
-- =============================================================================

local orig_select, orig_input = vim.ui.select, vim.ui.input
local disk_before = table.concat(vim.fn.readfile(target), '\n')
vim.cmd('edit ' .. vim.fn.fnameescape(target))
local note_buf, note_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()

do
  -- Create a tag that does not exist. The fallback puts "+ new tag…" first;
  -- the stub also moves focus away first, as a picker window would.
  local offered, titles = nil, {}
  vim.ui.select = function(items, opts, on_choice)
    titles[#titles + 1] = opts.prompt
    offered = items
    vim.cmd('new')
    on_choice(items[1], 1)
  end
  vim.ui.input = function(_, on_input) on_input('  Acústica ') end

  vim.cmd('PKMTag add')
  vim.wait(1000, function()
    return vim.tbl_contains(vim.api.nvim_buf_call(note_buf, buffer_tags), 'acústica')
  end, 10)

  check("bare :PKMTag add opens the tag picker",
    titles[1] == 'Add tag to this note', tostring(titles[1]))
  check("it lists vault tags ranked for the note (plus the new-tag entry)",
    offered and offered[1].is_new_prompt and offered[2].tag == 'quantum',
    offered and tostring(offered[2] and offered[2].tag))
  check("the new tag lands in the NOTE's buffer, normalised",
    vim.tbl_contains(vim.api.nvim_buf_call(note_buf, buffer_tags), 'acústica'))
  check("focus returned to the note's window", vim.api.nvim_get_current_win() == note_win)
  check("the write is buffer-only (disk unchanged, buffer modified)",
    table.concat(vim.fn.readfile(target), '\n') == disk_before
      and vim.bo[note_buf].modified)
  vim.cmd('only')
end

do
  -- Remove: only the note's own tags are offered, the unsaved one included.
  local offered
  vim.ui.select = function(items, _, on_choice)
    offered = items
    on_choice(row_for(items, 'physics'), 1)
  end

  vim.cmd('PKMTag remove')
  vim.wait(1000, function()
    return not vim.tbl_contains(buffer_tags(), 'physics')
  end, 10)

  check("bare :PKMTag remove lists only the note's tags, in its order",
    offered and table.concat(tag_order(offered), ',') == 'physics,acústica',
    offered and table.concat(tag_order(offered), ','))
  check("a saved tag carries its vault count",
    offered and row_for(offered, 'physics').count == 3)
  check("the chosen tag is removed from the buffer",
    not vim.tbl_contains(buffer_tags(), 'physics')
      and vim.tbl_contains(buffer_tags(), 'acústica'),
    table.concat(buffer_tags(), ','))
end

vim.ui.select, vim.ui.input = orig_select, orig_input
vim.cmd('bwipeout! ' .. note_buf)

-- =============================================================================
-- Default keymaps
-- =============================================================================

check("<leader>ta is bound to :PKMTag add",
  vim.fn.maparg('<leader>ta', 'n'):find('PKMTag add', 1, true) ~= nil,
  vim.fn.maparg('<leader>ta', 'n'))
check("<leader>tr is bound to :PKMTag remove",
  vim.fn.maparg('<leader>tr', 'n'):find('PKMTag remove', 1, true) ~= nil,
  vim.fn.maparg('<leader>tr', 'n'))

-- =============================================================================
-- pkm.api still folds through the shared helper
-- =============================================================================

do
  local res = require('pkm.api').find('orcamentaria')
  local hit = false
  for _, t in ipairs(res.tags or {}) do
    if (type(t) == 'table' and t.tag or t) == 'orçamentária' then hit = true end
  end
  check("api.find stays accent-insensitive", res.ok and hit, vim.inspect(res.tags))
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
