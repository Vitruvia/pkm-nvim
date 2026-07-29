-- test/test_v1120_p1.lua
-- v1.12.0 Ph1 — pkm.args, the one reading of a command's arguments.
--
-- Two things are proved here. First, the structural parser on its own: verb
-- dispatch, the escape that lets a name win over a verb, key=value, the bang,
-- and the is_verb flag that lets each caller decide what a non-verb first word
-- means. Second, that the two parsers migrated onto it — views and tags — still
-- honour their old contracts exactly, because the point of migrating was to
-- prove one reading serves both rather than becoming a third.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1120_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local args  = require('pkm.args')
local views = require('pkm.views')
local tags  = require('pkm.tags')

--- Shorthand: parse fargs against a spec.
local function P(fargs, spec)
  return args.parse({ fargs = fargs }, spec)
end

print("== no verbs declared: everything is positional ==")

do
  local p = P({ 'a', 'b', 'c' }, {})
  check("verb is nil", p.verb == nil)
  check("is_verb is false", p.is_verb == false)
  check("every token is positional", #p.positional == 3 and p.positional[3] == 'c')
  check("named is empty", next(p.named) == nil)
  check("bang defaults to false", p.bang == false)
end

print("\n== the bang is read straight from opts ==")

do
  local p = args.parse({ fargs = {}, bang = true }, {})
  check("bang is true when opts.bang is set", p.bang == true)
end

print("\n== key=value only when the spec opts in ==")

do
  local off = P({ 'note', 'title=Foo' }, {})
  check("with named off, key=value stays positional",
    #off.positional == 2 and off.positional[2] == 'title=Foo', off.positional[2])
  check("and named is empty", next(off.named) == nil)

  local on = P({ 'note', 'title=Foo', 'where=left' }, { named = true })
  check("with named on, key=value is pulled out",
    on.named.title == 'Foo' and on.named.where == 'left', vim.inspect(on.named))
  check("and the bare word stays positional",
    #on.positional == 1 and on.positional[1] == 'note', vim.inspect(on.positional))
  check("a value keeps its own '=' (title=a=b → a=b)",
    P({ 'title=a=b' }, { named = true }).named.title == 'a=b')
  check("a key must start with a letter, so 1=x is positional",
    P({ '1=x' }, { named = true }).positional[1] == '1=x')
end

print("\n== verb dispatch ==")

local vspec = { verbs = { 'add', 'remove' }, default = 'open' }

do
  local empty = P({}, vspec)
  check("no tokens → the default verb", empty.verb == 'open' and empty.is_verb == false)
  check("and nothing positional", #empty.positional == 0)

  local verb = P({ 'add', 'x', 'y' }, vspec)
  check("a declared verb is taken as the verb", verb.verb == 'add' and verb.is_verb == true)
  check("and the rest is its argument", #verb.positional == 2 and verb.positional[1] == 'x')

  local ci = P({ 'ADD', 'x' }, vspec)
  check("the verb match is case-insensitive", ci.verb == 'add' and ci.is_verb == true)

  local nonverb = P({ 'leituras' }, vspec)
  check("a non-verb first word → default verb", nonverb.verb == 'open')
  check("marked is_verb=false, so the caller can tell", nonverb.is_verb == false)
  check("and the word is kept as positional", nonverb.positional[1] == 'leituras')
end

print("\n== the escape: a name wins over a verb ==")

do
  -- The whole positional names an existing thing → default verb, keep it all.
  local known = { ['add'] = true, ['add leituras'] = true }
  local spec  = {
    verbs = { 'add', 'remove' }, default = 'open',
    escape = function(joined) return known[joined] == true end,
  }

  local named_add = P({ 'add' }, spec)
  check("'add' when a view is named 'add' → the default verb",
    named_add.verb == 'open' and named_add.is_verb == false)
  check("and 'add' is kept as the argument", named_add.positional[1] == 'add')

  local verb_add = P({ 'add', 'projeto' }, spec)
  check("'add projeto' (not a known whole name) → the verb",
    verb_add.verb == 'add' and verb_add.is_verb == true)

  local whole = P({ 'add', 'leituras' }, spec)
  check("'add leituras' when a view is named exactly that → default verb",
    whole.verb == 'open' and #whole.positional == 2)
end

print("\n== complete_verbs draws from the same table ==")

do
  local all = args.complete_verbs(vspec, '')
  check("an empty prefix offers every verb", #all == 2 and all[1] == 'add')
  local re = args.complete_verbs(vspec, 're')
  check("a prefix filters", #re == 1 and re[1] == 'remove', vim.inspect(re))
  check("case-insensitively", args.complete_verbs(vspec, 'RE')[1] == 'remove')
  check("a prefix matching nothing is empty", #args.complete_verbs(vspec, 'zz') == 0)
end

print("\n== views.parse_command_args still honours its contract ==")

do
  local names = { 'leituras', 'projeto ativo', 'add' }
  local function parsed(fargs)
    local mode, name, err = views.parse_command_args(fargs, names)
    return string.format('%s|%s|%s', mode, tostring(name), tostring(err))
  end

  check("no args → open, no name", parsed({}) == 'open|nil|nil', parsed({}))
  check("a bare name opens it", parsed({ 'leituras' }) == 'open|leituras|nil')
  check("a spaced name needs no quoting",
    parsed({ 'projeto', 'ativo' }) == 'open|projeto ativo|nil')
  check("add names a view", parsed({ 'add', 'leituras' }) == 'add|leituras|nil')
  check("the verb is case-insensitive", parsed({ 'ADD', 'leituras' }) == 'add|leituras|nil')
  check("a verb with a spaced view name",
    parsed({ 'add', 'projeto', 'ativo' }) == 'add|projeto ativo|nil')
  check("a verb with no name leaves it unchosen",
    parsed({ 'add' }) == 'add|nil|nil' or
    select(1, views.parse_command_args({ 'add' }, { 'leituras' })) == 'add',
    parsed({ 'add' }))
  check("a verb naming nothing that exists is an error",
    parsed({ 'add', 'inexistente' }) == "add|inexistente|no view named 'inexistente'")
  check("an unknown word is still an open",
    parsed({ 'inexistente' }) == 'open|inexistente|nil')
  check("a view named 'add' wins over the verb when it is the whole argument",
    select(1, views.parse_command_args({ 'add' }, { 'add' })) == 'open')
  check("but 'add <name>' is still the verb",
    select(1, views.parse_command_args({ 'add', 'leituras' }, { 'add', 'leituras' })) == 'add')
end

print("\n== tags.parse_command_args still honours its contract ==")

do
  check("no argument means browse", tags.parse_command_args({}) == 'browse')
  check("an explicit browse is browse", tags.parse_command_args({ 'browse' }) == 'browse')

  local mode, ops, header = tags.parse_command_args({ 'add', 'draft' })
  check("add carries its tag", mode == 'add' and ops.add[1] == 'draft')
  check("with a header", header == "Add tag 'draft'", header)

  ops = select(2, tags.parse_command_args({ 'remove', 'DRAFT' }))
  check("a tag is normalised on the way in", ops.remove[1] == 'draft')

  ops = select(2, tags.parse_command_args({ 'rename', 'draf', 'draft' }))
  check("rename carries both", ops.rename[1].from == 'draf' and ops.rename[1].to == 'draft')

  mode, ops = tags.parse_command_args({ 'add' })
  check("a mode without its tag still selects the mode", mode == 'add' and ops == nil)

  local quoted = select(2, tags.parse_command_args({ 'add', '"ring forge"' }))
  check("a quoted multi-word tag loses its quotes", quoted.add[1] == 'ring forge')

  local function err_of(fargs) return select(4, tags.parse_command_args(fargs)) end
  check("rename without a destination is refused", err_of({ 'rename', 'draf' }) ~= nil)
  check("renaming onto itself is refused", err_of({ 'rename', 'draft', 'DRAFT' }) ~= nil)
  check("an unknown mode is refused, and named so",
    (err_of({ 'sprinkle', 'draft' }) or ''):find('unknown mode', 1, true) ~= nil,
    err_of({ 'sprinkle', 'draft' }))
  check("an empty tag is refused", err_of({ 'add', '   ' }) ~= nil)
  check("a surplus argument is refused", err_of({ 'add', 'a', 'b' }) ~= nil)
  check("browse takes no argument", err_of({ 'browse', 'draft' }) ~= nil)
  check("a refusal returns no mode", tags.parse_command_args({ 'rename', 'draf' }) == nil)
end

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
