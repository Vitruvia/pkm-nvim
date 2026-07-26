-- test/test_v180_p9.lua
-- Tests for v1.8.0 Phase 9: view membership by tags.
--
-- "Put this note in that view" means "make the view's filter match", and tags
-- are the only part of a note a bulk operation may rewrite for that. So the
-- whole difficulty is in filter.tag_sets: which tag sets satisfy an expression,
-- and which parts of it no tag can reach. That is pure, and is where the weight
-- of this file sits. The flow on top is then exercised over a real corpus.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v180_p9.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== view membership by tags (v1.8.0 Ph9) ==")

local pkm    = require('pkm')
local utils  = require('pkm.utils')
local yaml   = require('pkm.yaml')
local index  = require('pkm.index')
local filter = require('pkm.filter')
local views  = require('pkm.views')
local tags   = require('pkm.tags')

---@param expr string
---@return table[] alternatives
local function sets_for(expr)
  local tree = assert(filter.parse(expr), 'could not parse: ' .. expr)
  return filter.tag_sets(tree)
end

---@param alt table
---@return string  e.g. "+a,+b|-c"
local function sig(alt)
  local add = table.concat(alt.add, ',')
  local rem = table.concat(alt.remove, ',')
  return (add ~= '' and '+' .. add or '') .. (rem ~= '' and '|-' .. rem or '')
end

---@param alts table[]
---@return string
local function all_sigs(alts)
  local out = {}
  for _, alt in ipairs(alts) do out[#out + 1] = sig(alt) end
  table.sort(out)
  return table.concat(out, '  ')
end

-- =============================================================================
-- tag_sets: the shape of "what would make this match"
-- =============================================================================

do
  local alts = sets_for('tag:rpg')
  check("a single tag is one alternative that adds it",
    #alts == 1 and sig(alts[1]) == '+rpg', all_sigs(alts))
  check("and it is not blocked by anything", #alts[1].blockers == 0)

  alts = sets_for('tag:rpg AND tag:forge')
  check("AND needs both tags in the same alternative",
    #alts == 1 and sig(alts[1]) == '+forge,rpg', all_sigs(alts))

  alts = sets_for('tag:rpg OR tag:forge')
  check("OR offers one alternative per branch",
    #alts == 2 and all_sigs(alts) == '+forge  +rpg', all_sigs(alts))

  alts = sets_for('NOT tag:draft')
  check("a negated tag asks for its removal",
    #alts == 1 and sig(alts[1]) == '|-draft', all_sigs(alts))

  alts = sets_for('tag:rpg AND NOT tag:draft')
  check("add and remove combine in one alternative",
    #alts == 1 and sig(alts[1]) == '+rpg|-draft', all_sigs(alts))
end

do
  -- De Morgan: the negation of a group flips the connective.
  local alts = sets_for('NOT (tag:a AND tag:b)')
  check("NOT over AND becomes a choice of removals",
    #alts == 2 and all_sigs(alts) == '|-a  |-b', all_sigs(alts))

  alts = sets_for('NOT (tag:a OR tag:b)')
  check("NOT over OR requires removing both",
    #alts == 1 and sig(alts[1]) == '|-a,b', all_sigs(alts))

  -- `NOT NOT x` is a parse error by design (NOT binds to an atom), so the
  -- parenthesised form is what a double negative looks like in this DSL.
  alts = sets_for('NOT (NOT tag:a)')
  check("a double negative is the plain requirement",
    #alts == 1 and sig(alts[1]) == '+a', all_sigs(alts))
end

do
  local alts = sets_for('(tag:a OR tag:b) AND tag:c')
  check("a disjunction inside a conjunction distributes",
    #alts == 2 and all_sigs(alts) == '+a,c  +b,c', all_sigs(alts))
end

do
  -- Self-contradiction has no alternative at all.
  check("a filter no note can satisfy yields nothing",
    #sets_for('tag:a AND NOT tag:a') == 0)
end

-- =============================================================================
-- Blockers: what tags cannot reach
-- =============================================================================

do
  local alts = sets_for('tag:rpg AND title:seneca')
  check("a title condition is carried as a blocker",
    #alts == 1 and #alts[1].blockers == 1
    and alts[1].blockers[1] == 'title:seneca',
    alts[1] and table.concat(alts[1].blockers, ',') or 'none')
  check("while the tag part is still reported",
    sig(alts[1]) == '+rpg', sig(alts[1]))

  alts = sets_for('tag:rpg OR title:seneca')
  local clean = 0
  for _, alt in ipairs(alts) do
    if #alt.blockers == 0 then clean = clean + 1 end
  end
  check("an OR keeps the reachable branch free of blockers",
    #alts == 2 and clean == 1, string.format('%d of %d clean', clean, #alts))

  for _, expr in ipairs({ 'type:bib', 'text:kant', 'filename:0042', 'any:x' }) do
    local a = sets_for(expr)
    check("'" .. expr .. "' is a blocker, not a tag requirement",
      #a == 1 and #a[1].blockers == 1 and #a[1].add == 0 and #a[1].remove == 0,
      expr)
  end

  local negated = sets_for('NOT type:bib')
  check("a negated non-tag condition is still a blocker, and says so",
    negated[1].blockers[1] == 'NOT type:bib', negated[1].blockers[1])
end

do
  check("an empty tree yields nothing", #filter.tag_sets(nil) == 0)
end

-- =============================================================================
-- view_flow over a real corpus
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

local n1 = write_note('1101_note_Um',   {})
local n2 = write_note('1102_note_Dois', { 'draft' })
index.rebuild()

views.save('ph9', 'tag:projeto AND NOT tag:draft')
views.save('ph9_titulo', 'title:impossivel')

do
  local tree = views.get_tree('ph9')
  check("a view's composed filter is reachable", tree ~= nil)

  local alts = filter.tag_sets(tree)
  check("membership needs the tag added and the other removed",
    #alts == 1 and sig(alts[1]) == '+projeto|-draft', all_sigs(alts))
end

do
  -- Adding: one alternative, so no menu; the confirmation is the float here.
  local before = #views.match_all('ph9')
  check("neither note is in the view yet", before == 0, tostring(before))

  tags.view_flow({ n1, n2 }, 'add', { view = 'ph9' })
  vim.wait(500, function() return vim.bo.buftype == 'nofile' end, 10)

  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("the confirmation names the view and the tag change",
    shown:find("Add to 'ph9'", 1, true) ~= nil
    and shown:find('+projeto', 1, true) ~= nil, shown:sub(1, 120))
  check("and the note carrying draft shows it being dropped",
    shown:find('draft  →  projeto', 1, true) ~= nil, shown)

  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
  vim.wait(1000, function() return #views.match_all('ph9') == 2 end, 10)

  check("both notes are now in the view", #views.match_all('ph9') == 2,
    tostring(#views.match_all('ph9')))
end

do
  -- Removing is the mirror: satisfy the negation. This filter has two ways out
  -- — drop the tag it requires, or add the one it excludes — so the flow asks
  -- which, and that choice is a judgement it must not make alone.
  local offered
  local orig = vim.ui.select
  vim.ui.select = function(labels, _, on_choice)
    offered = table.concat(labels, ' | ')
    on_choice(labels[1], 1)
  end

  tags.view_flow({ n1 }, 'remove', { view = 'ph9' })
  vim.wait(500, function() return vim.bo.buftype == 'nofile' end, 10)
  vim.ui.select = orig

  check("both ways out of the view are offered",
    offered ~= nil and offered:find('-projeto', 1, true) ~= nil
    and offered:find('+draft', 1, true) ~= nil, tostring(offered))

  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("the confirmation names the chosen way out",
    shown:find("Remove from 'ph9'", 1, true) ~= nil, shown:sub(1, 120))

  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
  vim.wait(1000, function() return #views.match_all('ph9') == 1 end, 10)

  check("one note left the view", #views.match_all('ph9') == 1,
    tostring(#views.match_all('ph9')))
end

do
  -- A view tags cannot satisfy must say so instead of writing anything.
  local wrote = false
  local orig  = vim.ui.select
  vim.ui.select = function() wrote = true end

  tags.view_flow({ n1 }, 'add', { view = 'ph9_titulo' })
  vim.wait(300, function() return wrote end, 10)

  vim.ui.select = orig
  check("a title-only view opens no confirmation", wrote == false)
  check("and nothing was written",
    #views.match_all('ph9_titulo') == 0, tostring(#views.match_all('ph9_titulo')))
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
