-- test/test_v180_p4.lua
-- Tests for v1.8.0 Phase 4: bulk actions start from the selection.
--
-- Three seams, all reachable without a panel: the action registry (data, so it
-- is enumerable — the shape the future pkm.api will expose), the scope list
-- (pure, and the reason a one-option menu no longer appears), and the :PKMTags
-- argument contract (pure, and what a script or an advanced user depends on).
-- The batch entry point itself is driven over a disposable corpus.
--
-- Runs against a real headless Neovim instance on the disposable temp root
-- created by test/min_init.lua — never the live Notes tree.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v180_p4.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== bulk actions from the selection (v1.8.0 Ph4) ==")

local pkm     = require('pkm')
local utils   = require('pkm.utils')
local yaml    = require('pkm.yaml')
local index   = require('pkm.index')
local tags    = require('pkm.tags')
local actions = require('pkm.actions')

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

local p1 = write_note('0501_note_one', { 'draf' })
local p2 = write_note('0502_note_two', { 'draf', 'physics' })
index.rebuild()

-- =============================================================================
-- The action registry
-- =============================================================================

do
  local list = actions.list()
  check("the registry is a non-empty ordered list", #list >= 3, '#' .. #list)

  local ids = {}
  for _, action in ipairs(list) do ids[#ids + 1] = action.id end
  check("the three tag operations are registered",
    table.concat(ids, ','):find('tag_add', 1, true) ~= nil
    and table.concat(ids, ','):find('tag_remove', 1, true) ~= nil
    and table.concat(ids, ','):find('tag_rename', 1, true) ~= nil,
    table.concat(ids, ','))

  check("every action carries a label and something to run", (function()
    for _, action in ipairs(list) do
      if type(action.label) ~= 'string' or action.label == '' then return false end
      if type(action.run) ~= 'function' then return false end
    end
    return true
  end)())

  check("get() finds a registered action", actions.get('tag_rename') ~= nil)
  check("and returns nil for an unknown id", actions.get('nope') == nil)
end

do
  -- run_id dispatches without any menu; substituting the action's run proves
  -- which paths reached it.
  local action  = actions.get('tag_add')
  local orig    = action.run
  local got
  action.run = function(paths) got = paths end

  local ok = actions.run_id('tag_add', { p1, p2 })
  check("run_id dispatches to the action with the given notes",
    ok and got ~= nil and #got == 2, got and ('#' .. #got) or 'never ran')

  got = nil
  check("an unknown id is refused", actions.run_id('nope', { p1 }) == false)
  check("and so is an empty selection", actions.run_id('tag_add', {}) == false)
  check("neither one runs anything", got == nil)

  action.run = orig
end

-- =============================================================================
-- scope_choices(): the menu that no longer appears
-- =============================================================================

do
  local alone = tags.scope_choices(nil, nil)
  check("with no note and no view, only the filter scope remains",
    #alone == 1 and alone[1].kind == 'filter', '#' .. #alone)

  local with_note = tags.scope_choices('C:/notes/0042_note_Kant.md', nil)
  check("an open markdown note adds its own scope",
    #with_note == 2 and with_note[1].kind == 'note', '#' .. #with_note)
  check("and the label names the note",
    with_note[1].label:find('0042_note_Kant', 1, true) ~= nil, with_note[1].label)

  check("a non-markdown buffer contributes nothing",
    #tags.scope_choices('C:/notes/README.txt', nil) == 1)
  check("an unnamed buffer contributes nothing",
    #tags.scope_choices('', nil) == 1)

  local full = tags.scope_choices('C:/notes/0042_note_Kant.md', 'physics')
  check("an active view adds a third scope", #full == 3, '#' .. #full)
  check("and the filter scope is always last",
    full[#full].kind == 'filter', full[#full].kind)
end

-- =============================================================================
-- parse_command_args(): the :PKMTags contract
-- =============================================================================

do
  check("no argument means browse", tags.parse_command_args({}) == 'browse')
  check("an explicit browse is browse", tags.parse_command_args({ 'browse' }) == 'browse')

  local mode, ops, header = tags.parse_command_args({ 'add', 'draft' })
  check("add carries its tag as an operation set",
    mode == 'add' and ops.add[1] == 'draft', tostring(mode))
  check("and a header naming it",
    header == "Add tag 'draft'", tostring(header))

  mode, ops = tags.parse_command_args({ 'remove', 'DRAFT' })
  check("a tag is normalised on the way in",
    mode == 'remove' and ops.remove[1] == 'draft', ops and ops.remove[1] or nil)

  mode, ops, header = tags.parse_command_args({ 'rename', 'draf', 'draft' })
  check("rename carries both tags",
    mode == 'rename' and ops.rename[1].from == 'draf' and ops.rename[1].to == 'draft',
    tostring(mode))
  check("and its header states the change",
    header == "Rename 'draf' to 'draft'", tostring(header))

  mode, ops = tags.parse_command_args({ 'add' })
  check("a mode without its tag still selects the mode, and prompts later",
    mode == 'add' and ops == nil, tostring(mode))

  local quoted = select(2, tags.parse_command_args({ 'add', '"ring forge"' }))
  check("a quoted multi-word tag loses its quotes",
    quoted.add[1] == 'ring forge', quoted.add[1])
end

do
  local function err_of(fargs)
    return select(4, tags.parse_command_args(fargs))
  end

  check("rename without a destination is refused",
    err_of({ 'rename', 'draf' }) ~= nil, tostring(err_of({ 'rename', 'draf' })))
  check("renaming a tag onto itself is refused",
    err_of({ 'rename', 'draft', 'DRAFT' }) ~= nil)
  check("an unknown mode is refused",
    (err_of({ 'sprinkle', 'draft' }) or ''):find('unknown mode', 1, true) ~= nil,
    tostring(err_of({ 'sprinkle', 'draft' })))
  check("an empty tag is refused", err_of({ 'add', '   ' }) ~= nil)
  check("a surplus argument is refused", err_of({ 'add', 'a', 'b' }) ~= nil)
  check("browse takes no argument", err_of({ 'browse', 'draft' }) ~= nil)
  check("a refusal returns no mode and no ops",
    tags.parse_command_args({ 'rename', 'draf' }) == nil)
end

-- =============================================================================
-- batch_on(): a selection that already exists, with the tag already decided
-- =============================================================================

do
  local ops = { rename = { { from = 'draf', to = 'draft' } } }

  -- Telescope is absent here, so the confirmation is the float; feeding <CR>
  -- accepts every listed note.
  tags.batch_on({ p1, p2 }, 'rename', ops, "Rename 'draf' to 'draft'")
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
  vim.wait(1000, function()
    return #tags.preview({ p1, p2 }, ops) == 0
  end, 10)

  check("the batch wrote both notes without any scope or tag prompt",
    #tags.preview({ p1, p2 }, ops) == 0,
    string.format('%d still to change', #tags.preview({ p1, p2 }, ops)))

  local entry = index.get(p2)
  check("and the index saw it without a rebuild", (function()
    for _, tag in ipairs(entry and entry.tags or {}) do
      if tag == 'draft' then return true end
    end
    return false
  end)(), entry and table.concat(entry.tags, ',') or 'no entry')
end

do
  local ran = false
  local orig = vim.ui.select
  vim.ui.select = function() ran = true end
  tags.batch_on({}, 'add')
  vim.ui.select = orig
  check("an empty selection opens nothing", ran == false)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
