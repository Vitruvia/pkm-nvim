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
  -- A named view is an answer: no menu, straight to the confirmation.
  local asked = false
  local orig  = vim.ui.select
  vim.ui.select = function() asked = true end

  tags.view_flow({ n1 }, 'add', { target = 'v190a' })
  vim.wait(500, function() return vim.bo.buftype == 'nofile' end, 10)
  vim.ui.select = orig

  check("naming the view asks nothing", asked == false)

  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("the confirmation names it", shown:find("Add to 'v190a'", 1, true) ~= nil,
    shown:sub(1, 120))

  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
  vim.wait(1000, function() return #views.match_all('v190a') == 1 end, 10)
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
  -- make the provenance win.
  local asked = false
  local orig  = vim.ui.select
  vim.ui.select = function() asked = true end

  tags.view_flow({ n1 }, 'remove', { view = 'v190b', target = 'v190a' })
  vim.wait(500, function() return vim.bo.buftype == 'nofile' end, 10)
  vim.ui.select = orig

  check("provenance does not override the named view", asked == false)
  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("the confirmation names the target, not the context",
    shown:find("Remove from 'v190a'", 1, true) ~= nil, shown:sub(1, 120))
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
