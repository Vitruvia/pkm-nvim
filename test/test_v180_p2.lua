-- test/test_v180_p2.lua
-- Tests for v1.8.0 Phase 2: the shared note picker and the batch tag preview.
--
-- The interactive flow itself (scope → notes → tag → preview → apply) is UI and
-- is smoke-tested by hand, but its two seams are not: the preview wording is a
-- pure function, and the float front-end of the picker is drivable headlessly —
-- which is exactly the front-end that decides what an unmarked <CR> confirms.
--
-- Runs against a real headless Neovim instance on the disposable temp root
-- created by test/min_init.lua — never the live Notes tree. Telescope is not on
-- the runtimepath here, so picker.select() takes its float path.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v180_p2.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== picker + batch preview (v1.8.0 Ph2) ==")

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

local p1 = write_note('0301_note_one', { 'alpha' })
local p2 = write_note('0302_note_two', { 'alpha', 'beta' })
local p3 = write_note('0303_note_three', {})
index.rebuild()

-- =============================================================================
-- preview(): which notes a batch would touch
--
-- (The wording of each row moved to tags.format_change in v1.8.0 Ph3, where the
-- confirmation became a picker; test_v180_p3 covers it.)
-- =============================================================================

do
  local plan = tags.preview({ p1, p2, p3 }, { add = { 'gamma' } })
  check("every note in the batch is reported as changing", #plan == 3,
    string.format('%d entries', #plan))
  check("an unaffected operation reports nothing",
    #tags.preview({ p1, p2, p3 }, { remove = { 'nowhere' } }) == 0)
end

-- =============================================================================
-- picker.select(): the float front-end confirms the whole list
-- =============================================================================

--- Feed keys to the float and wait for the callback.
---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

do
  local got
  picker.select({ p1, p2 }, { title = 'Test', hint = 'use listed' },
    function(paths) got = paths end)

  check("the float opened with a list", vim.bo.buftype == 'nofile',
    'buftype=' .. vim.bo.buftype)

  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("the title line states the count and the confirm key",
    shown:find('2 notes', 1, true) ~= nil and shown:find('<CR> use listed', 1, true) ~= nil,
    shown:sub(1, 90))
  check("rows show filename and tags",
    shown:find('0302_note_two.md  [alpha, beta]', 1, true) ~= nil, shown)

  feed('<CR>')
  vim.wait(1000, function() return got ~= nil end, 10)

  check("<CR> confirms every listed note", got ~= nil and #got == 2,
    got and ('#' .. #got) or 'callback never ran')
end

do
  local got, cancelled = nil, false
  picker.select({ p1, p2, p3 }, { title = 'Test', hint = 'use listed',
    on_cancel = function() cancelled = true end },
    function(paths) got = paths end)

  feed('q')
  vim.wait(1000, function() return cancelled end, 10)

  check("q cancels without confirming", cancelled and got == nil,
    got and ('confirmed ' .. #got) or nil)
end

do
  local ran = false
  picker.select({}, { title = 'Test', hint = 'use listed' }, function() ran = true end)
  check("an empty candidate list opens nothing", ran == false)
end

-- =============================================================================
-- picker.confirm(): the preview gate
-- =============================================================================

do
  local applied, cancelled = false, false
  picker.confirm({
    title      = 'Confirm',
    lines      = { '  header', '  • something' },
    on_confirm = function() applied = true end,
    on_cancel  = function() cancelled = true end,
  })

  feed('<Esc>')
  vim.wait(1000, function() return cancelled end, 10)
  check("Esc cancels the preview", cancelled and applied == false)

  picker.confirm({
    title      = 'Confirm',
    lines      = { '  header' },
    on_confirm = function() applied = true end,
  })
  feed('<CR>')
  vim.wait(1000, function() return applied end, 10)
  check("<CR> confirms the preview", applied)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
