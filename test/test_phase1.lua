-- =============================================================================
-- test/test_phase1.lua — Phase 1 test suite
-- =============================================================================
-- Tests filter.lua, index.lua, and export.lua integration.
-- Run with: :luafile P:/Active/pkm-nvim/test/test_phase1.lua
--
-- Requirements:
--   - PKM must be set up and running (require('pkm').setup() called)
--   - At least one note must exist in the PKM root
--
-- This script is read-only: it never creates, modifies, or deletes any note.
-- =============================================================================

local passed = 0
local failed = 0
local errors = {}

local function ok(name, condition, detail)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    table.insert(errors, string.format("  FAIL: %s%s", name, detail and (" — " .. detail) or ""))
  end
end

local function section(name)
  print(string.format("\n── %s ──", name))
end

local function report()
  print(string.format("\n%s", string.rep("=", 50)))
  if failed == 0 then
    print(string.format("ALL TESTS PASSED  (%d/%d)", passed, passed + failed))
  else
    print(string.format("FAILED: %d / %d", failed, passed + failed))
    for _, e in ipairs(errors) do print(e) end
  end
  print(string.rep("=", 50))
end

-- =============================================================================
-- 1. filter.lua — parse
-- =============================================================================
section("filter.parse")

local filter = require('pkm.filter')

-- Basic predicate
local t, err = filter.parse('tag:rpg')
ok("parse tag predicate",
  t ~= nil and t.type == 'PRED' and t.field == 'tag' and t.value == 'rpg', err)

-- AND
t, err = filter.parse('tag:rpg AND title:ring')
ok("parse AND", t ~= nil and t.type == 'AND' and #t.args == 2, err)

-- OR
t, err = filter.parse('tag:math OR tag:physics')
ok("parse OR", t ~= nil and t.type == 'OR' and #t.args == 2, err)

-- NOT
t, err = filter.parse('NOT tag:draft')
ok("parse NOT", t ~= nil and t.type == 'NOT' and t.args[1].field == 'tag', err)

-- Parentheses + complex
t, err = filter.parse('(tag:math OR tag:physics) AND NOT tag:draft')
ok("parse complex expression", t ~= nil and t.type == 'AND', err)

-- Quoted value with space
t, err = filter.parse('text:"Fourier transform"')
ok("parse quoted value with space",
  t ~= nil and t.type == 'PRED' and t.value == 'Fourier transform', err)

-- Case-insensitive keywords
t, err = filter.parse('tag:rpg and title:ring')
ok("parse lowercase AND keyword", t ~= nil and t.type == 'AND', err)

-- title field
t, err = filter.parse('title:ringforge')
ok("parse title field", t ~= nil and t.field == 'title', err)

-- text field
t, err = filter.parse('text:Fourier')
ok("parse text field", t ~= nil and t.field == 'text', err)

-- Error: empty string
t, err = filter.parse('')
ok("parse rejects empty string", t == nil and err ~= nil)

-- Error: unknown field
t, err = filter.parse('body:something')
ok("parse rejects unknown field", t == nil and err ~= nil)

-- Error: dangling AND
t, err = filter.parse('tag:rpg AND')
ok("parse rejects dangling AND", t == nil and err ~= nil)

-- Error: unclosed paren
t, err = filter.parse('(tag:rpg AND title:ring')
ok("parse rejects unclosed paren", t == nil and err ~= nil)

-- Error: unclosed quote
t, err = filter.parse('text:"unclosed')
ok("parse rejects unclosed quote", t == nil and err ~= nil)

-- =============================================================================
-- 2. filter.lua — eval
-- =============================================================================
section("filter.eval")

local function note(title, tags, body)
  return { path = '', title = title or '', tags = tags or {}, body = body or '' }
end

-- Tag exact match
local tree = filter.parse('tag:rpg')
ok("eval tag match",    filter.eval(tree, note('', {'rpg', 'math'})) == true)
ok("eval tag no match", filter.eval(tree, note('', {'math'})) == false)

-- Tag case-insensitive
tree = filter.parse('tag:RPG')
ok("eval tag case-insensitive", filter.eval(tree, note('', {'rpg'})) == true)

-- Tag is exact, not substring
tree = filter.parse('tag:rp')
ok("eval tag not substring", filter.eval(tree, note('', {'rpg'})) == false)

-- Title substring
tree = filter.parse('title:ring')
ok("eval title match",    filter.eval(tree, note('Ringforge RPG', {})) == true)
ok("eval title no match", filter.eval(tree, note('Fourier Analysis', {})) == false)

-- Title case-insensitive
tree = filter.parse('title:RING')
ok("eval title case-insensitive", filter.eval(tree, note('ringforge', {})) == true)

-- Text substring
tree = filter.parse('text:Fourier')
ok("eval text match",    filter.eval(tree, note('', {}, 'Fourier transform')) == true)
ok("eval text no match", filter.eval(tree, note('', {}, 'unrelated content')) == false)

-- AND
tree = filter.parse('tag:rpg AND title:ring')
ok("eval AND both true",  filter.eval(tree, note('Ringforge', {'rpg'})) == true)
ok("eval AND one false",  filter.eval(tree, note('Ringforge', {'math'})) == false)
ok("eval AND both false", filter.eval(tree, note('Other', {'math'})) == false)

-- OR
tree = filter.parse('tag:math OR tag:physics')
ok("eval OR first true",  filter.eval(tree, note('', {'math'})) == true)
ok("eval OR second true", filter.eval(tree, note('', {'physics'})) == true)
ok("eval OR both false",  filter.eval(tree, note('', {'biology'})) == false)

-- NOT
tree = filter.parse('NOT tag:draft')
ok("eval NOT negates true",  filter.eval(tree, note('', {'draft'})) == false)
ok("eval NOT negates false", filter.eval(tree, note('', {'final'})) == true)

-- Complex
tree = filter.parse('(tag:math OR tag:physics) AND NOT tag:draft')
ok("eval complex match",    filter.eval(tree, note('', {'math', 'final'})) == true)
ok("eval complex filtered", filter.eval(tree, note('', {'math', 'draft'})) == false)
ok("eval complex no tag",   filter.eval(tree, note('', {'biology'})) == false)

-- nil/empty tolerance
tree = filter.parse('tag:rpg')
ok("eval nil tags",  filter.eval(tree, note('', nil)) == false)
ok("eval nil title", filter.eval(filter.parse('title:x'), note(nil, {})) == false)
ok("eval nil body",  filter.eval(filter.parse('text:x'), note('', {}, nil)) == false)

-- =============================================================================
-- 3. filter.lua — from_legacy
-- =============================================================================
section("filter.from_legacy")

-- Empty → nil
local leg = filter.from_legacy({})
ok("from_legacy empty → nil", leg == nil)

-- Single tags_any → PRED
leg = filter.from_legacy({ tags_any = {'math'} })
ok("from_legacy single tags_any → PRED",
  leg ~= nil and leg.type == 'PRED' and leg.value == 'math')

-- Multiple tags_any → OR
leg = filter.from_legacy({ tags_any = {'math', 'physics'} })
ok("from_legacy multi tags_any → OR",
  leg ~= nil and leg.type == 'OR' and #leg.args == 2)

-- tags_all two items → AND
leg = filter.from_legacy({ tags_all = {'math', 'proof'} })
ok("from_legacy tags_all two items → AND", leg ~= nil and leg.type == 'AND')

-- title only → PRED title
leg = filter.from_legacy({ title = 'Fourier' })
ok("from_legacy title only → PRED title",
  leg ~= nil and leg.type == 'PRED' and leg.field == 'title')

-- combined → AND at top level
leg = filter.from_legacy({ tags_any = {'math'}, title = 'Analysis' })
ok("from_legacy combined → AND", leg ~= nil and leg.type == 'AND')

-- backward compat: evaluates correctly
leg = filter.from_legacy({ tags_any = {'math', 'physics'}, title = 'Analysis' })
ok("from_legacy eval combined match",
  filter.eval(leg, note('Real Analysis', {'math'})) == true)
ok("from_legacy eval combined no match",
  filter.eval(leg, note('RPG Notes', {'rpg'})) == false)

-- =============================================================================
-- 4. index.lua — state and read-only operations
-- =============================================================================
section("index — state")

local index = require('pkm.index')

-- is_built reflects whether get_all has been called
-- (may already be built if this script is re-run in the same session)
local was_built = index.is_built()
local entries = index.get_all()
ok("index built after get_all", index.is_built() == true)
ok("get_all returns table",     type(entries) == 'table')

if #entries > 0 then
  local e = entries[1]
  ok("entry has path",  type(e.path)  == 'string' and e.path  ~= '')
  ok("entry has title", type(e.title) == 'string')
  ok("entry has tags",  type(e.tags)  == 'table')
  ok("entry has body",  type(e.body)  == 'string')
  ok("entry has mtime", type(e.mtime) == 'number')

  -- get by path
  local found = index.get(e.path)
  ok("index.get returns entry for known path", found ~= nil)
  ok("index.get entry path matches",           found and found.path == e.path)

  -- get returns nil for garbage path
  ok("index.get returns nil for unknown path",
    index.get('/nonexistent/path/that/does/not/exist.md') == nil)

  -- invalidate on existing file: entry should persist (file still exists)
  local path_before = e.path
  index.invalidate(e.path)
  local after = index.get(e.path)
  ok("invalidate on existing file keeps entry",  after ~= nil)
  ok("invalidate preserves path field",          after and after.path == path_before)

  -- invalidate on non-existent path: no error, no entry created
  index.invalidate('/nonexistent/pkm/note.md')
  ok("invalidate on nonexistent path leaves no entry",
    index.get('/nonexistent/pkm/note.md') == nil)

else
  print("  NOTE: no notes found in PKM root — entry shape tests skipped")
end

-- rebuild: resets and repopulates
index.rebuild()
ok("index still built after rebuild", index.is_built() == true)
local after_rebuild = index.get_all()
ok("rebuild returns entries table", type(after_rebuild) == 'table')

-- entry count stable across rebuild
ok("entry count stable after rebuild", #after_rebuild == #entries)

-- =============================================================================
-- 5. export integration
-- =============================================================================
section("export integration")

local export = require('pkm.export')

-- collect_files empty filter
local all = export.collect_files({})
ok("collect_files empty filter returns table", type(all) == 'table')

if #all > 0 then
  -- All paths are strings
  local all_strings = true
  for _, p in ipairs(all) do
    if type(p) ~= 'string' then all_strings = false end
  end
  ok("collect_files all paths are strings", all_strings)

  -- match_file empty filter → true
  ok("match_file empty filter → true", export.match_file(all[1], {}) == true)

  -- match_file impossible tag → false
  ok("match_file impossible tag → false",
    export.match_file(all[1], { tags_all = {'__xyzzy_impossible__'} }) == false)

  -- collect_files impossible filter → empty
  local none = export.collect_files({ tags_all = {'__xyzzy_impossible__'} })
  ok("collect_files impossible filter → empty", #none == 0)

  -- Results are sorted by filename
  if #all > 1 then
    local sorted = true
    for i = 2, #all do
      local a = vim.fn.fnamemodify(all[i-1], ':t')
      local b = vim.fn.fnamemodify(all[i],   ':t')
      if a > b then sorted = false end
    end
    ok("collect_files result is sorted by filename", sorted)
  end

  -- index and export see the same note set
  local index_paths = {}
  for _, e in ipairs(index.get_all()) do index_paths[e.path] = true end
  local export_paths = {}
  for _, p in ipairs(all) do export_paths[p] = true end

  local sets_match = true
  for p in pairs(index_paths)  do if not export_paths[p] then sets_match = false end end
  for p in pairs(export_paths) do if not index_paths[p]  then sets_match = false end end
  ok("index and export see the same note set", sets_match)

else
  print("  NOTE: no notes found — export path tests skipped")
end

-- =============================================================================
-- 6. Views
-- =============================================================================
section("views")

local views = require('pkm.views')

-- list() returns a table
local names = views.list()
ok("views.list returns table", type(names) == 'table')

-- list() is sorted
if #names > 1 then
  local sorted = true
  for i = 2, #names do
    if names[i] < names[i-1] then sorted = false end
  end
  ok("views.list is sorted", sorted)
end

-- match_all on nonexistent view → empty + error, no crash
local result = views.match_all('__nonexistent_view__')
ok("match_all nonexistent view returns empty table", type(result) == 'table' and #result == 0)

-- If any views are defined, test match_all and open
if #names > 0 then
  local first = names[1]
  local paths = views.match_all(first)
  ok("match_all returns table", type(paths) == 'table')

  -- All returned paths are strings
  local all_strings = true
  for _, p in ipairs(paths) do
    if type(p) ~= 'string' then all_strings = false end
  end
  ok("match_all all paths are strings", all_strings)

  -- Results are sorted by filename
  if #paths > 1 then
    local sorted = true
    for i = 2, #paths do
      local a = vim.fn.fnamemodify(paths[i-1], ':t')
      local b = vim.fn.fnamemodify(paths[i],   ':t')
      if a > b then sorted = false end
    end
    ok("match_all result is sorted", sorted)
  end

  -- match_all and export.collect_files with equivalent filter agree
  local config = require('pkm').config
  local expr   = config.projects[first]
  local tree   = require('pkm.filter').parse(expr)
  if tree then
    local export  = require('pkm.export')
    -- Build a legacy-style filter isn't possible for arbitrary DSL expressions,
    -- so compare match_all directly against manual index filtering.
    local filter  = require('pkm.filter')
    local entries = require('pkm.index').get_all()
    local manual  = {}
    for _, e in ipairs(entries) do
      if filter.eval(tree, e) then manual[e.path] = true end
    end
    local match_set = {}
    for _, p in ipairs(paths) do match_set[p] = true end
    local sets_agree = true
    for p in pairs(manual)    do if not match_set[p] then sets_agree = false end end
    for p in pairs(match_set) do if not manual[p]    then sets_agree = false end end
    ok("match_all agrees with direct index filter", sets_agree)
  end
else
  print("  NOTE: no views defined in config.projects — define at least one to test match_all")
end

-- =============================================================================
-- Report
-- =============================================================================
report()
