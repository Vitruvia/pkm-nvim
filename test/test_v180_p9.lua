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
-- A third view exists so that "which view?" is a real question: with one view
-- defined, every ordering rule below would be untestable.
views.save('ph9_outra', 'tag:outra')

--- Stand in for `vim.ui.select`, recording what it was offered and answering
--- with the row whose view name is `pick`.
---@param pick string
---@return function restore   Put the real `vim.ui.select` back
---@return function offered   The labels the menu was given
local function stub_select(pick)
  local seen, orig = nil, vim.ui.select
  -- These menus now go through `picker.choose`, which hands `vim.ui.select` the
  -- rows themselves plus a `format_item`; the fallback is what headless sees,
  -- since Telescope never loads here.
  vim.ui.select = function(items, opts, on_choice)
    local labels = {}
    for i, item in ipairs(items) do
      labels[i] = opts.format_item and opts.format_item(item) or tostring(item)
    end
    seen = labels

    for i, label in ipairs(labels) do
      if label == pick or label:sub(1, #pick + 2) == pick .. '  ' then
        on_choice(items[i], i)
        return
      end
    end
    on_choice(items[1], 1)
  end
  return function() vim.ui.select = orig end, function() return seen or {} end
end

---@param labels string[]
---@return string
local function names_of(labels)
  local out = {}
  for i, label in ipairs(labels) do out[i] = label:match('^(%S+)') end
  return table.concat(out, ' | ')
end

do
  local tree = views.get_tree('ph9')
  check("a view's composed filter is reachable", tree ~= nil)

  local alts = filter.tag_sets(tree)
  check("membership needs the tag added and the other removed",
    #alts == 1 and sig(alts[1]) == '+projeto|-draft', all_sigs(alts))
end

do
  -- Adding from inside a view: the context view is not the answer. Every view
  -- is on offer, because "where these notes came from" says nothing about
  -- where they should go.
  local before = #views.match_all('ph9')
  check("neither note is in the view yet", before == 0, tostring(before))

  local restore, offered = stub_select('ph9')
  tags.view_flow({ n1, n2 }, 'add', { view = 'ph9' })
  vim.wait(500, function() return vim.bo.buftype == 'nofile' end, 10)
  restore()

  local labels = offered()
  check("adding offers every view, not just the one we came from",
    #labels == 3, names_of(labels))
  check("with nothing yet in any of them, the order is plain alphabetical",
    names_of(labels) == 'ph9 | ph9_outra | ph9_titulo', names_of(labels))

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
  local restore, offered_labels = stub_select('-projeto')

  tags.view_flow({ n1 }, 'remove', { view = 'ph9' })
  vim.wait(500, function() return vim.bo.buftype == 'nofile' end, 10)
  restore()

  local offered = table.concat(offered_labels(), ' | ')
  check("both ways out of the view are offered",
    offered:find('-projeto', 1, true) ~= nil
    and offered:find('+draft', 1, true) ~= nil, offered)

  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("the confirmation names the chosen way out",
    shown:find("Remove from 'ph9'", 1, true) ~= nil, shown:sub(1, 120))

  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
  vim.wait(1000, function() return #views.match_all('ph9') == 1 end, 10)

  check("one note left the view", #views.match_all('ph9') == 1,
    tostring(#views.match_all('ph9')))
  check("removal asked no view menu when only one view held the note",
    offered ~= nil and offered:find('ph9_outra', 1, true) == nil,
    tostring(offered))
end

-- =============================================================================
-- Which view — the choice ctx.view used to make on its own (v1.8.1 Ph1)
-- =============================================================================
--
-- The defect: chosen from inside a view, an operation could only reach that
-- same view. Adding notes to it was pointless (they were already there) and no
-- other view was reachable at all. `ctx.view` may order the menu; it may not
-- answer it.

do
  -- The membership question itself, read-only: n2 is in ph9, nothing is in the
  -- other two.
  local rows = tags.view_membership({ n1, n2 })
  local by_name = {}
  for _, row in ipairs(rows) do by_name[row.name] = row end

  check("membership reports every defined view", #rows == 3, tostring(#rows))
  check("ph9 holds exactly the note that stayed in it",
    #by_name['ph9'].paths == 1 and by_name['ph9'].paths[1] == n2,
    tostring(#by_name['ph9'].paths))
  check("a view matching nothing reports nothing",
    #by_name['ph9_outra'].paths == 0 and by_name['ph9_outra'].total == 2,
    tostring(#by_name['ph9_outra'].paths))
  check("an unindexed path is counted in no total",
    #tags.view_membership({ '/nao/existe.md' })[1].paths == 0
    and tags.view_membership({ '/nao/existe.md' })[1].total == 0)
end

do
  -- Adding, from inside the view the selection is already wholly in: that view
  -- is the one useless answer, so it sinks to the bottom instead of being
  -- assumed.
  local restore, offered = stub_select('ph9_outra')
  tags.view_flow({ n2 }, 'add', { view = 'ph9' })
  vim.wait(500, function() return vim.bo.buftype == 'nofile' end, 10)
  restore()

  local labels = offered()
  check("the view the note is already in is offered last",
    names_of(labels) == 'ph9_outra | ph9_titulo | ph9', names_of(labels))
  check("and it is labelled as already holding the selection",
    labels[3]:find('already in', 1, true) ~= nil, labels[3])

  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("a different view than the context one is reachable",
    shown:find("Add to 'ph9_outra'", 1, true) ~= nil, shown:sub(1, 120))

  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
  vim.wait(1000, function() return #views.match_all('ph9_outra') == 1 end, 10)
  check("the note joined the view it was not chosen from",
    #views.match_all('ph9_outra') == 1, tostring(#views.match_all('ph9_outra')))
end

do
  -- Removing, with the note now in two views: both are offered, the context
  -- one leads, and a view the note is not in is absent.
  local restore, offered = stub_select('ph9_outra')
  tags.view_flow({ n2 }, 'remove', { view = 'ph9' })
  vim.wait(500, function() return vim.bo.buftype == 'nofile' end, 10)
  restore()

  local labels = offered()
  check("removal offers only the views the selection is in",
    names_of(labels) == 'ph9 | ph9_outra', names_of(labels))
  check("and says how much of the selection each holds",
    labels[1]:find('all 1 selected', 1, true) ~= nil, labels[1])

  local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check("a view other than the context one can be left",
    shown:find("Remove from 'ph9_outra'", 1, true) ~= nil, shown:sub(1, 120))

  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
  vim.wait(1000, function() return #views.match_all('ph9_outra') == 0 end, 10)
  check("the note left the view it was not chosen from",
    #views.match_all('ph9_outra') == 0, tostring(#views.match_all('ph9_outra')))
end

do
  -- A selection in no view at all: removal has nothing to offer and must say
  -- so rather than present a menu of impossible choices.
  local said = {}
  local orig_notify = vim.notify
  vim.notify = function(msg) said[#said + 1] = tostring(msg) end

  local opened = false
  local orig_select = vim.ui.select
  vim.ui.select = function() opened = true end

  tags.view_flow({ n1 }, 'remove', { view = 'ph9' })
  vim.wait(300, function() return #said > 0 end, 10)

  vim.ui.select = orig_select
  vim.notify = orig_notify

  check("removal opens no menu when the notes are in no view", opened == false)
  check("and says why",
    table.concat(said, ' '):find('belongs to a view', 1, true) ~= nil,
    table.concat(said, ' '))
end

do
  -- A view tags cannot satisfy must say so instead of writing anything. The
  -- view is now chosen from the menu like any other, so the refusal has to
  -- survive that extra hop.
  local said = {}
  local orig_notify = vim.notify
  vim.notify = function(msg) said[#said + 1] = tostring(msg) end

  local restore = stub_select('ph9_titulo')
  tags.view_flow({ n1 }, 'add', { view = 'ph9_titulo' })
  vim.wait(300, function() return #said > 0 end, 10)
  restore()
  vim.notify = orig_notify

  local text = table.concat(said, ' ')
  check("a title-only view names the condition in the way",
    text:find('cannot be satisfied with tags alone', 1, true) ~= nil, text)
  check("and nothing was written",
    #views.match_all('ph9_titulo') == 0, tostring(#views.match_all('ph9_titulo')))
end

do
  -- The chooser these menus now run through. Telescope never loads headless,
  -- so what is exercised here is the fallback contract: rows in, rendered by
  -- the caller, answered with the row itself.
  local picker = require('pkm.picker')

  local opened = false
  local orig = vim.ui.select
  vim.ui.select = function() opened = true end
  picker.choose({}, { title = 'vazio', display = tostring }, function() end)
  vim.ui.select = orig
  check("choose opens nothing for an empty list", opened == false)

  local answered, rendered
  orig = vim.ui.select
  vim.ui.select = function(items, opts, on_choice)
    rendered = opts.format_item(items[2])
    on_choice(items[2], 2)
  end
  picker.choose({ { name = 'um' }, { name = 'dois' } }, {
    title   = 'qual',
    display = function(row) return 'view ' .. row.name end,
  }, function(row, idx) answered = row.name .. '@' .. idx end)
  vim.wait(200, function() return answered ~= nil end, 10)
  vim.ui.select = orig

  check("the caller renders the row and gets it back with its position",
    rendered == 'view dois' and answered == 'dois@2',
    tostring(rendered) .. ' / ' .. tostring(answered))

  local went_back = false
  orig = vim.ui.select
  vim.ui.select = function(_, _, on_choice) on_choice(nil, nil) end
  picker.choose({ { name = 'um' } }, {
    title   = 'qual',
    display = function(row) return row.name end,
    on_back = function() went_back = true end,
  }, function() end)
  vim.wait(200, function() return went_back end, 10)
  vim.ui.select = orig

  check("cancelling the fallback goes back when the caller offered a way",
    went_back)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
