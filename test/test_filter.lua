-- =============================================================================
-- test/test_filter.lua — Test suite for pkm.filter (with any predicate)
-- =============================================================================
-- Run from Neovim after plugin load:
--   :luafile test/test_filter.lua
--
-- Covers:
--   1. parse — existing expressions (field predicates, boolean ops, quotes)
--   2. parse — new any-predicate forms (bare word, standalone quoted, unknown field)
--   3. parse — error cases (empty, dangling ops, unclosed delimiters)
--   4. eval  — existing field predicates (tag, title, text, filename)
--   5. eval  — any predicate (title, body, filename, tag substring)
--   6. eval  — boolean operators (AND, OR, NOT, complex)
--   7. from_legacy — backward compatibility
-- =============================================================================

local filter = require('pkm.filter')

local pass = 0
local fail = 0

local function ok(label, condition)
  if condition then
    pass = pass + 1
    print("  PASS  " .. label)
  else
    fail = fail + 1
    print("  FAIL  " .. label)
  end
end

local function section(name)
  print("\n--- " .. name .. " ---")
end

--- Build a minimal note data table for eval tests.
---@param title    string|nil
---@param tags     string[]|nil
---@param body     string|nil
---@param filename string|nil  File stem without extension (default "test")
local function note(title, tags, body, filename)
  return {
    path     = '/fake/' .. (filename or 'test') .. '.md',
    filename = filename or 'test',
    title    = title   or '',
    tags     = tags    or {},
    body     = body    or '',
  }
end

local t, err

-- =============================================================================
-- 1. parse — existing expressions (unchanged semantics)
-- =============================================================================
section("parse — existing field predicates")

t, err = filter.parse('tag:rpg')
ok("tag: parses",                  t ~= nil and err == nil)
ok("tag: field is 'tag'",          t ~= nil and t.field == 'tag')
ok("tag: value is 'rpg'",          t ~= nil and t.value == 'rpg')

t, err = filter.parse('title:ring')
ok("title: parses",                t ~= nil and err == nil)
ok("title: field is 'title'",      t ~= nil and t.field == 'title')

t, err = filter.parse('text:fourier')
ok("text: parses",                 t ~= nil and err == nil)
ok("text: field is 'text'",        t ~= nil and t.field == 'text')

t, err = filter.parse('filename:0042')
ok("filename: parses",             t ~= nil and err == nil)
ok("filename: field is 'filename'", t ~= nil and t.field == 'filename')

-- Explicit any: field
t, err = filter.parse('any:ring')
ok("any: explicit form parses",    t ~= nil and err == nil)
ok("any: field is 'any'",          t ~= nil and t.field == 'any')
ok("any: value is 'ring'",         t ~= nil and t.value == 'ring')

-- Quoted field values
t, err = filter.parse('title:"ring forge"')
ok('title:"quoted" parses',        t ~= nil and err == nil)
ok('title:"quoted" field',         t ~= nil and t.field == 'title')
ok('title:"quoted" value',         t ~= nil and t.value == 'ring forge')

t, err = filter.parse('text:"Fourier transform"')
ok('text:"quoted" parses',         t ~= nil and err == nil)
ok('text:"quoted" value',          t ~= nil and t.value == 'Fourier transform')

-- Boolean operators
t, err = filter.parse('tag:rpg AND title:ring')
ok("AND expression parses",        t ~= nil and t.type == 'AND')
ok("AND has two args",             t ~= nil and #t.args == 2)

t, err = filter.parse('tag:math OR tag:physics')
ok("OR expression parses",         t ~= nil and t.type == 'OR')
ok("OR has two args",              t ~= nil and #t.args == 2)

t, err = filter.parse('NOT tag:draft')
ok("NOT expression parses",        t ~= nil and t.type == 'NOT')
ok("NOT has one arg",              t ~= nil and #t.args == 1)

-- Parentheses
t, err = filter.parse('(tag:math OR tag:physics) AND NOT tag:draft')
ok("complex expression parses",    t ~= nil and t.type == 'AND')

-- Case-insensitive keywords
t, err = filter.parse('tag:math and title:ring')
ok("lowercase 'and' keyword",      t ~= nil and t.type == 'AND')

t, err = filter.parse('tag:math And title:ring')
ok("mixed-case 'And' keyword",     t ~= nil and t.type == 'AND')

-- =============================================================================
-- 2. parse — new any-predicate forms
-- =============================================================================
section("parse — new any-predicate forms")

-- Bare word → any
t, err = filter.parse('fourier')
ok("bare word parses",                  t ~= nil and err == nil)
ok("bare word → field 'any'",           t ~= nil and t.field == 'any')
ok("bare word → correct value",         t ~= nil and t.value == 'fourier')

-- Bare word with uppercase (value preserved as-is)
t, err = filter.parse('Fourier')
ok("bare word uppercase preserves case", t ~= nil and t.value == 'Fourier')

-- Standalone quoted string → any
t, err = filter.parse('"ring forge"')
ok('standalone "..." parses',           t ~= nil and err == nil)
ok('standalone "..." → field any',      t ~= nil and t.field == 'any')
ok('standalone "..." → value',          t ~= nil and t.value == 'ring forge')

t, err = filter.parse('"and"')
ok('"and" quoted literal → any',        t ~= nil and t.field == 'any')
ok('"and" quoted literal → value',      t ~= nil and t.value == 'and')

-- Unknown field → any, full token as value
t, err = filter.parse('body:something')
ok("unknown field parses",              t ~= nil and err == nil)
ok("unknown field → field 'any'",       t ~= nil and t.field == 'any')
ok("unknown field → full token value",  t ~= nil and t.value == 'body:something')

-- URL-like: unknown field (http), full token as value
t, err = filter.parse('http://example.com')
ok("url-like token parses",             t ~= nil and err == nil)
ok("url-like token → field 'any'",      t ~= nil and t.field == 'any')
ok("url-like token → full value",       t ~= nil and t.value == 'http://example.com')

-- Bare word combined with field predicate
t, err = filter.parse('fourier AND tag:math')
ok("bare word AND tag: parses",         t ~= nil and t.type == 'AND')
if t and t.type == 'AND' and #t.args == 2 then
  ok("first arg: any:fourier",    t.args[1].field == 'any' and t.args[1].value == 'fourier')
  ok("second arg: tag:math",      t.args[2].field == 'tag'  and t.args[2].value == 'math')
else
  ok("first arg: any:fourier",  false)
  ok("second arg: tag:math",    false)
end

-- Bare word combined with another bare word via OR
t, err = filter.parse('fourier OR laplace')
ok("bare word OR bare word parses",     t ~= nil and t.type == 'OR')
if t and t.type == 'OR' and #t.args == 2 then
  ok("OR first arg: any",  t.args[1].field == 'any')
  ok("OR second arg: any", t.args[2].field == 'any')
else
  ok("OR first arg: any",  false)
  ok("OR second arg: any", false)
end

-- NOT bare word
t, err = filter.parse('NOT fourier')
ok("NOT bare word parses",              t ~= nil and t.type == 'NOT')
if t and t.type == 'NOT' then
  ok("NOT child: any:fourier", t.args[1].field == 'any' and t.args[1].value == 'fourier')
else
  ok("NOT child: any:fourier", false)
end

-- Mixed: standalone quoted AND field predicate
t, err = filter.parse('"ring forge" AND tag:rpg')
ok('"quoted" AND tag: parses',          t ~= nil and t.type == 'AND')

-- =============================================================================
-- 3. parse — error cases
-- =============================================================================
section("parse — error cases")

t, err = filter.parse('')
ok("empty string rejected",             t == nil and err ~= nil)

t, err = filter.parse('   ')
ok("whitespace-only rejected",          t == nil and err ~= nil)

t, err = filter.parse('tag:rpg AND')
ok("dangling AND rejected",             t == nil and err ~= nil)

t, err = filter.parse('OR tag:rpg')
ok("leading OR rejected",               t == nil and err ~= nil)

t, err = filter.parse('(tag:rpg AND title:ring')
ok("unclosed paren rejected",           t == nil and err ~= nil)

t, err = filter.parse('text:"unclosed')
ok("unclosed quote rejected",           t == nil and err ~= nil)

t, err = filter.parse('tag:')
ok("known field with no value rejected", t == nil and err ~= nil)

-- Bare AND is a keyword, not a value (rejected as dangling)
t, err = filter.parse('AND')
ok("lone AND keyword rejected",         t == nil and err ~= nil)

t, err = filter.parse('OR')
ok("lone OR keyword rejected",          t == nil and err ~= nil)

-- =============================================================================
-- 4. eval — existing field predicates
-- =============================================================================
section("eval — tag: (exact, case-insensitive)")

local tree

tree = filter.parse('tag:rpg')
ok("tag: exact match → true",      filter.eval(tree, note('', {'rpg', 'math'})) == true)
ok("tag: not present → false",     filter.eval(tree, note('', {'math'})) == false)
ok("tag: case-insensitive",        filter.eval(filter.parse('tag:RPG'), note('', {'rpg'})) == true)
ok("tag: is exact, not substring", filter.eval(filter.parse('tag:rp'), note('', {'rpg'})) == false)
ok("tag: nil tags → false",        filter.eval(tree, note('', nil)) == false)
ok("tag: empty tags → false",      filter.eval(tree, note('', {})) == false)

section("eval — title: (substring, case-insensitive)")

tree = filter.parse('title:ring')
ok("title: substring → true",      filter.eval(tree, note('Ringforge RPG', {})) == true)
ok("title: no match → false",      filter.eval(tree, note('Fourier Analysis', {})) == false)
ok("title: case-insensitive",      filter.eval(filter.parse('title:RING'), note('ringforge', {})) == true)
ok("title: nil title → false",     filter.eval(filter.parse('title:x'), note(nil, {})) == false)
ok("title: empty title → false",   filter.eval(filter.parse('title:x'), note('', {})) == false)

section("eval — text: (body substring)")

tree = filter.parse('text:fourier')
ok("text: body match → true",      filter.eval(tree, note('', {}, 'Fourier transform')) == true)
ok("text: body no match → false",  filter.eval(tree, note('', {}, 'unrelated')) == false)
ok("text: case-insensitive",       filter.eval(filter.parse('text:FOURIER'), note('', {}, 'fourier')) == true)
ok("text: nil body → false",       filter.eval(filter.parse('text:x'), note('', {}, nil)) == false)

section("eval — filename: (substring)")

tree = filter.parse('filename:0042')
ok("filename: match → true",       filter.eval(tree, note('', {}, '', '0042_note_Title')) == true)
ok("filename: no match → false",   filter.eval(tree, note('', {}, '', '0099_note_Other')) == false)
ok("filename: case-insensitive",
  filter.eval(filter.parse('filename:NOTE'), note('', {}, '', '0042_note_Title')) == true)

-- =============================================================================
-- 5. eval — any predicate (new)
-- =============================================================================
section("eval — any predicate (new)")

-- Bare word 'fourier' → PRED{any, 'fourier'}
tree = filter.parse('fourier')
ok("any: matches title",            filter.eval(tree, note('Fourier Analysis', {})) == true)
ok("any: matches body",             filter.eval(tree, note('', {}, 'see Fourier transform')) == true)
ok("any: matches filename",         filter.eval(tree, note('', {}, '', '0042_note_fourier')) == true)
ok("any: matches tag (substring)",  filter.eval(tree, note('', {'fourier-analysis'})) == true)
ok("any: no match in any field",    filter.eval(tree, note('Laplace', {}, 'laplace', '0001_note_laplace')) == false)

-- any: case-insensitive across all fields
tree = filter.parse('FOURIER')
ok("any: case-insensitive title",  filter.eval(tree, note('fourier', {})) == true)
ok("any: case-insensitive body",   filter.eval(tree, note('', {}, 'fourier')) == true)
ok("any: case-insensitive filename",
  filter.eval(tree, note('', {}, '', '0042_note_fourier')) == true)

-- any: vs tag: for tag matching
-- any: is SUBSTRING; tag: is EXACT
tree = filter.parse('any:math')
ok("any: tag substring (mathematics contains math)",
  filter.eval(tree, note('', {'mathematics'})) == true)
ok("any: tag exact value also matches",
  filter.eval(tree, note('', {'math'})) == true)

local tag_exact = filter.parse('tag:math')
ok("tag: does NOT match 'mathematics' (exact only)",
  filter.eval(tag_exact, note('', {'mathematics'})) == false)
ok("tag: DOES match 'math' (exact)",
  filter.eval(tag_exact, note('', {'math'})) == true)

-- Explicit any: field behaves identically to bare word
tree = filter.parse('any:fourier')
ok("any: explicit matches title",    filter.eval(tree, note('Fourier', {})) == true)
ok("any: explicit matches body",     filter.eval(tree, note('', {}, 'fourier')) == true)
ok("any: explicit matches filename",
  filter.eval(tree, note('', {}, '', '0042_note_fourier')) == true)

-- Unknown field token: value = 'body:something' (with colon)
-- Matches only when a field literally contains 'body:something'
tree = filter.parse('body:something')  -- → PRED{any, 'body:something'}
ok("unknown field: value includes colon",  tree ~= nil and tree.value == 'body:something')
ok("unknown field: matches title containing full token",
  filter.eval(tree, note('body:something here', {})) == true)
ok("unknown field: does NOT match note whose body just contains 'something'",
  filter.eval(tree, note('Analysis', {}, 'something relevant')) == false)

-- Standalone quoted string
tree = filter.parse('"ring forge"')
ok('standalone quoted: matches title',  filter.eval(tree, note('Ring Forge RPG', {})) == true)
ok('standalone quoted: matches body',   filter.eval(tree, note('', {}, 'ring forge system')) == true)
ok('standalone quoted: phrase must be contiguous',
  filter.eval(tree, note('ring and forge', {}, 'ring and forge')) == false)

-- any: nil/empty tolerance
tree = filter.parse('fourier')
ok("any: nil title OK",     filter.eval(tree, { path='', filename='test', title=nil,  tags={}, body='' }) == false)
ok("any: nil body OK",      filter.eval(tree, { path='', filename='test', title='',   tags={}, body=nil }) == false)
ok("any: nil filename OK",  filter.eval(tree, { path='', filename=nil, title='fourier', tags={}, body='' }) == true)

-- =============================================================================
-- 6. eval — boolean operators
-- =============================================================================
section("eval — boolean operators")

-- AND
tree = filter.parse('tag:rpg AND title:ring')
ok("AND both true",   filter.eval(tree, note('Ringforge', {'rpg'})) == true)
ok("AND left false",  filter.eval(tree, note('Ringforge', {'math'})) == false)
ok("AND right false", filter.eval(tree, note('Unrelated', {'rpg'})) == false)
ok("AND both false",  filter.eval(tree, note('Unrelated', {'math'})) == false)

-- OR
tree = filter.parse('tag:math OR tag:physics')
ok("OR left true",    filter.eval(tree, note('', {'math'})) == true)
ok("OR right true",   filter.eval(tree, note('', {'physics'})) == true)
ok("OR both false",   filter.eval(tree, note('', {'biology'})) == false)

-- NOT
tree = filter.parse('NOT tag:draft')
ok("NOT negates true",   filter.eval(tree, note('', {'draft'})) == false)
ok("NOT negates false",  filter.eval(tree, note('', {'final'})) == true)

-- Complex
tree = filter.parse('(tag:math OR tag:physics) AND NOT tag:draft')
ok("complex: match",         filter.eval(tree, note('', {'math', 'final'})) == true)
ok("complex: NOT blocks",    filter.eval(tree, note('', {'math', 'draft'})) == false)
ok("complex: OR fails",      filter.eval(tree, note('', {'biology'})) == false)

-- any combined with tag
tree = filter.parse('fourier AND tag:math')
ok("any AND tag: both true",    filter.eval(tree, note('Fourier Analysis', {'math'})) == true)
ok("any AND tag: any false",    filter.eval(tree, note('Laplace', {'math'})) == false)
ok("any AND tag: tag false",    filter.eval(tree, note('Fourier Analysis', {'physics'})) == false)

-- NOT on bare word
tree = filter.parse('NOT fourier')
ok("NOT any: excludes fourier in title",  filter.eval(tree, note('Fourier Analysis', {})) == false)
ok("NOT any: allows other notes",         filter.eval(tree, note('Laplace Transform', {})) == true)

-- =============================================================================
-- 7. from_legacy — backward compatibility
-- =============================================================================
section("from_legacy — backward compatibility")

local leg

leg = filter.from_legacy({})
ok("empty table → nil",               leg == nil)

leg = filter.from_legacy({ tags_any = {'math'} })
ok("single tags_any → PRED",          leg ~= nil and leg.type == 'PRED')
ok("single tags_any → tag field",     leg ~= nil and leg.field == 'tag')
ok("single tags_any → value",         leg ~= nil and leg.value == 'math')

leg = filter.from_legacy({ tags_any = {'math', 'physics'} })
ok("multi tags_any → OR",             leg ~= nil and leg.type == 'OR')
ok("multi tags_any → 2 args",         leg ~= nil and #leg.args == 2)

leg = filter.from_legacy({ tags_all = {'math', 'proof'} })
ok("tags_all 2 items → AND",          leg ~= nil and leg.type == 'AND')
ok("tags_all AND has 2 args",         leg ~= nil and #leg.args == 2)

leg = filter.from_legacy({ title = 'Fourier' })
ok("title only → PRED title",         leg ~= nil and leg.type == 'PRED' and leg.field == 'title')
ok("title value correct",             leg ~= nil and leg.value == 'Fourier')

leg = filter.from_legacy({ text = 'transform' })
ok("text only → PRED text",           leg ~= nil and leg.field == 'text')

leg = filter.from_legacy({ tags_any = {'math'}, title = 'Analysis' })
ok("combined → AND",                  leg ~= nil and leg.type == 'AND')

-- Evaluate legacy trees for correctness
leg = filter.from_legacy({ tags_any = {'math', 'physics'}, title = 'Analysis' })
ok("legacy eval: match",    filter.eval(leg, note('Real Analysis', {'math'})) == true)
ok("legacy eval: no match", filter.eval(leg, note('RPG Notes', {'rpg'})) == false)

leg = filter.from_legacy({ tags_all = {'math', 'proof'} })
ok("tags_all both present: true",  filter.eval(leg, note('', {'math', 'proof', 'other'})) == true)
ok("tags_all one missing: false",  filter.eval(leg, note('', {'math'})) == false)

-- from_legacy should not be affected by the any predicate (its fields are fixed)
leg = filter.from_legacy({ tags_any = {'math'} })
ok("from_legacy tag: still exact (not any)", filter.eval(leg, note('', {'mathematics'})) == false)

-- =============================================================================
-- Summary
-- =============================================================================
local total = pass + fail
print(string.format("\n=== Results: %d / %d passed ===", pass, total))
if fail > 0 then
  vim.notify(
    string.format("[pkm test] filter: %d passed, %d FAILED", pass, fail),
    vim.log.levels.WARN)
else
  vim.notify(
    string.format("[pkm test] filter: all %d tests passed", pass),
    vim.log.levels.INFO)
end
