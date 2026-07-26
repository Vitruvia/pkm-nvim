-- test/test_v190_p1.lua
-- Tests for v1.9.0 Phase 1: :PKMView add|remove <name> on the current note.
--
-- One command carries three meanings, so the reading has to be a rule rather
-- than a guess: if the arguments spell an existing view name exactly, it is an
-- open; only then are `add` and `remove` verbs. That rule is pure, and most of
-- this file exercises it directly. The flow on top is then run over a real
-- corpus, including the case the rule exists for — a view actually named
-- "add".
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v190_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== :PKMView on the current note (v1.9.0 Ph1) ==")

local pkm   = require('pkm')
local utils = require('pkm.utils')
local yaml  = require('pkm.yaml')
local index = require('pkm.index')
local views = require('pkm.views')
local tags  = require('pkm.tags')

-- =============================================================================
-- parse_command_args: pure
-- =============================================================================

local names = { 'leituras', 'projeto ativo', 'add' }

---@param fargs string[]
---@return string
local function parsed(fargs)
  local mode, name, err = views.parse_command_args(fargs, names)
  return string.format('%s|%s|%s', mode, tostring(name), tostring(err))
end

check("no arguments means open with no name",
  parsed({}) == 'open|nil|nil', parsed({}))
check("a bare name opens it",
  parsed({ 'leituras' }) == 'open|leituras|nil', parsed({ 'leituras' }))
check("a name with spaces needs no quoting",
  parsed({ 'projeto', 'ativo' }) == 'open|projeto ativo|nil',
  parsed({ 'projeto', 'ativo' }))
check("add names a view",
  parsed({ 'add', 'leituras' }) == 'add|leituras|nil',
  parsed({ 'add', 'leituras' }))
check("remove names a view",
  parsed({ 'remove', 'leituras' }) == 'remove|leituras|nil',
  parsed({ 'remove', 'leituras' }))
check("the verb is case-insensitive",
  parsed({ 'ADD', 'leituras' }) == 'add|leituras|nil',
  parsed({ 'ADD', 'leituras' }))
check("a verb with a multi-word view name",
  parsed({ 'add', 'projeto', 'ativo' }) == 'add|projeto ativo|nil',
  parsed({ 'add', 'projeto', 'ativo' }))
-- Against a vault with no view called "add" — the ordinary case.
local plain = { 'leituras' }
check("a verb with no name leaves the view unchosen",
  string.format('%s|%s', views.parse_command_args({ 'add' }, plain),
    tostring(select(2, views.parse_command_args({ 'add' }, plain)))) == 'add|nil',
  tostring(views.parse_command_args({ 'add' }, plain)))
check("a verb naming nothing that exists is an error, not a guess",
  parsed({ 'add', 'inexistente' }) == "add|inexistente|no view named 'inexistente'",
  parsed({ 'add', 'inexistente' }))
check("an unknown word is still an open, reported by whoever opens",
  parsed({ 'inexistente' }) == 'open|inexistente|nil', parsed({ 'inexistente' }))

-- The rule exists for exactly this: a view named after a verb.
check("a view named 'add' wins over the verb when it is the whole argument",
  select(1, views.parse_command_args({ 'add' }, { 'add' })) == 'open',
  tostring(select(1, views.parse_command_args({ 'add' }, { 'add' }))))
check("while 'add <name>' is still the verb even when a view is named 'add'",
  select(1, views.parse_command_args({ 'add', 'leituras' }, { 'add', 'leituras' }))
    == 'add')

-- =============================================================================
-- The flow, over a real corpus
-- =============================================================================

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

---@param stem string
---@param note_tags string[]
---@return string path
local function write_note(stem, note_tags)
  local lines = { '---' }
  vim.list_extend(lines, yaml.generate_yaml({ title = stem, tags = note_tags }))
  vim.list_extend(lines, { '---', '', 'corpo' })
  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

local n1 = write_note('4101_note_Atual', {})
index.rebuild()

views.save('v190a', 'tag:alfa')
views.save('v190b', 'tag:beta')

do
  -- Typing the whole operation *is* the operation: one note, the view named,
  -- and adding is not a removal, so there is no screen at all.
  local asked = false
  local orig  = vim.ui.select
  vim.ui.select = function() asked = true end
  local buftype_before = vim.bo.buftype

  tags.view_flow({ n1 }, 'add', { target = 'v190a' })
  vim.wait(1000, function() return #views.match_all('v190a') == 1 end, 10)
  vim.ui.select = orig

  check("naming the view asks nothing", asked == false)
  check("and opens no panel either", vim.bo.buftype == buftype_before,
    vim.bo.buftype)
  check("the note joined the named view", #views.match_all('v190a') == 1,
    tostring(#views.match_all('v190a')))
end

do
  -- Removing from a view the note is not in is not an operation.
  local said = {}
  local orig_notify = vim.notify
  vim.notify = function(msg) said[#said + 1] = tostring(msg) end
  local orig_select = vim.ui.select
  local asked = false
  vim.ui.select = function() asked = true end

  tags.view_flow({ n1 }, 'remove', { target = 'v190b' })
  vim.wait(300, function() return #said > 0 end, 10)

  vim.ui.select = orig_select
  vim.notify = orig_notify

  check("removing from a view it is not in opens nothing", asked == false)
  check("and says so",
    table.concat(said, ' '):find('nothing to remove', 1, true) ~= nil,
    table.concat(said, ' '))
  check("the note is still where it was", #views.match_all('v190a') == 1)
end

do
  -- A name that does not exist is refused before anything is computed.
  local said = {}
  local orig_notify = vim.notify
  vim.notify = function(msg) said[#said + 1] = tostring(msg) end

  tags.view_flow({ n1 }, 'add', { target = 'v190_inexistente' })
  vim.wait(300, function() return #said > 0 end, 10)
  vim.notify = orig_notify

  check("an unknown target is refused",
    table.concat(said, ' '):find('no view named', 1, true) ~= nil,
    table.concat(said, ' '))
end

do
  -- ctx.target decides; ctx.view still only orders. Both together must not
  -- make the provenance win. And removal keeps its gate even when typed —
  -- doc/PRINCIPLES.md: every removal confirms.
  local asked = false
  local orig  = vim.ui.select
  vim.ui.select = function() asked = true end

  tags.view_flow({ n1 }, 'remove', { view = 'v190b', target = 'v190a' })
  vim.wait(500, function() return vim.bo.buftype == 'nofile' end, 10)
  vim.ui.select = orig

  check("provenance does not override the named view", asked == false)
  check("a typed removal still puts a gate in front of it",
    vim.bo.buftype == 'nofile', vim.bo.buftype)

  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("the gate names the target, not the context",
    shown:find("Remove from 'v190a'", 1, true) ~= nil, shown:sub(1, 120))
  check("and it is a gate, not a list promising a choice",
    shown:find('<CR> apply', 1, true) ~= nil
    and shown:find('apply to listed', 1, true) == nil, shown:sub(1, 160))

  -- Back out, so the float does not outlive this block and swallow the next
  -- block's keys.
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('q', true, false, true), 'x', false)
  vim.wait(300, function() return vim.bo.buftype ~= 'nofile' end, 10)
end

-- =============================================================================
-- What the alternative says it will change
-- =============================================================================
--
-- `filter.tag_sets` answers "what does this view require", so an alternative
-- carries the whole requirement — including tags the note already has. Offering
-- "+afo, +concursos" to a note that already carries `afo` describes the
-- destination rather than the change.

do
  local n2 = write_note('4102_note_Meio', { 'afo' })
  index.rebuild()
  views.save('v190c', 'tag:afo AND tag:concursos')

  local said = {}
  local orig_notify = vim.notify
  vim.notify = function(msg) said[#said + 1] = tostring(msg) end

  tags.view_flow({ n2 }, 'add', { target = 'v190c' })
  vim.wait(1000, function() return #views.match_all('v190c') == 1 end, 10)
  vim.notify = orig_notify

  local text = table.concat(said, ' ')
  check("the tag already carried is not offered again",
    text:find('+afo', 1, true) == nil, text)
  check("only the missing one is named",
    text:find('+concursos', 1, true) ~= nil, text)
  check("and the note is in the view either way",
    #views.match_all('v190c') == 1, tostring(#views.match_all('v190c')))
end

do
  -- One note, no view named: still a gate rather than a list, because there is
  -- nothing to narrow.
  local n3 = write_note('4103_note_Sozinha', {})
  index.rebuild()

  -- No `target`: the view is chosen from the menu, so this is the `<C-a>`
  -- path, not the typed one, and the gate must appear.
  local orig = vim.ui.select
  vim.ui.select = function(items, opts, on_choice)
    for i, item in ipairs(items) do
      local label = opts.format_item and opts.format_item(item) or tostring(item)
      if label:match('^v190b') then on_choice(item, i) return end
    end
    on_choice(items[1], 1)
  end

  tags.view_flow({ n3 }, 'add', {})
  vim.wait(500, function() return vim.bo.buftype == 'nofile' end, 10)
  vim.ui.select = orig

  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("a single note gets a gate, not a note picker",
    shown:find('<CR> apply', 1, true) ~= nil
    and shown:find('apply to listed', 1, true) == nil, shown:sub(1, 160))

  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
  vim.wait(1000, function() return #views.match_all('v190b') == 1 end, 10)
  check("and confirming it writes", #views.match_all('v190b') == 1,
    tostring(#views.match_all('v190b')))
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
