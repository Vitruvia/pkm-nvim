-- test/test_v161_p3.lua
-- Tests for v1.6.1 Phase 3: the counting path of pkm.views.
--
-- Covers the two changes of that phase:
--   1. count_all()/count_many() must agree with #match_all() in every case,
--      including subprojects, empty results and unknown view names — they are
--      the overview screens' new source of the "(N)" counts.
--   2. match_all()'s precomputed sort keys must produce byte-for-byte the same
--      order as the previous comparator (fnamemodify inside table.sort), which
--      the reference implementation below recreates on the same input.
--
-- Runs against a real headless Neovim instance on the disposable temp root
-- created by test/min_init.lua — never the live Notes tree.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v161_p3.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== views counting path (v1.6.1 Ph3) ==")

local pkm   = require('pkm')
local utils = require('pkm.utils')
local views = require('pkm.views')
local index = require('pkm.index')

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

--- Write one fixture note and return its absolute path.
---@param stem string    File stem (no extension)
---@param tags string[]  Frontmatter tags
---@return string path
local function write_note(stem, tags)
  local lines = { '---', string.format('title: "%s"', stem), 'tags:' }
  for _, t in ipairs(tags) do lines[#lines + 1] = '  - ' .. t end
  lines[#lines + 1] = '---'
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'body of ' .. stem

  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

-- Sort-order fixture. The stems are chosen so the basename comparison is not
-- interchangeable with a stem comparison: '-' (0x2D) sorts before '.' (0x2E),
-- '_' (0x5F) and '0' (0x30) after it, so "sa-b.md" < "sa.md" < "sa0.md" <
-- "sa_b.md" while the bare stems would order "sa" first. Any accidental change
-- of sort key shows up here. (All stems differ in more than case: Windows
-- filesystems are case-insensitive and would collapse two such files into one.)
for _, stem in ipairs({ 'sa', 'sa-b', 'sa_b', 'sb', 'sa0' }) do
  write_note(stem, { 'sortcase' })
end

write_note('00001_note_alpha_one', { 'alpha' })
write_note('00002_note_alpha_two', { 'alpha', 'beta' })
write_note('00003_note_beta_one',  { 'beta' })

index.rebuild()

check("fixture indexed", #index.get_all() >= 8,
  string.format("got %d entries", #index.get_all()))

-- Views: simple, subproject, and one that matches nothing.
views.save('t-alpha', 'tag:alpha')
views.save('t-sort', 'tag:sortcase')
views.save('t-empty', 'tag:nothing-matches-this')
views.save_subproject('t-alpha-beta', 't-alpha', 'tag:beta')

local names = { 't-alpha', 't-sort', 't-empty', 't-alpha-beta' }

-- =============================================================================
-- count_all() agrees with #match_all()
-- =============================================================================

for _, name in ipairs(names) do
  local from_paths = #views.match_all(name)
  local from_count = views.count_all(name)
  check(string.format("count_all('%s') == #match_all", name),
    from_count == from_paths,
    string.format("count_all=%d match_all=%d", from_count, from_paths))
end

-- Containment model (v1.81.0): a parent ROLLS UP its children (own filter OR the
-- union of descendants), and a subview matches its OWN filter, not narrowed by
-- the parent. t-alpha (tag:alpha) with child t-alpha-beta (tag:beta) therefore
-- matches alpha OR beta = {alpha_one, alpha_two, beta_one} = 3; the child alone
-- matches beta = {alpha_two, beta_one} = 2.
check("t-alpha rolls up its child (alpha OR beta = 3)", views.count_all('t-alpha') == 3,
  string.format("got %d", views.count_all('t-alpha')))
check("subview matches its own filter, not narrowed by the parent (beta = 2)",
  views.count_all('t-alpha-beta') == 2,
  string.format("got %d", views.count_all('t-alpha-beta')))
check("view matching nothing counts 0", views.count_all('t-empty') == 0,
  string.format("got %d", views.count_all('t-empty')))

-- =============================================================================
-- count_many() agrees with count_all(), one name at a time
-- =============================================================================

local batch = views.count_many(names)
local batch_ok = true
local batch_detail
for _, name in ipairs(names) do
  local single = views.count_all(name)
  if batch[name] ~= single then
    batch_ok = false
    batch_detail = string.format("%s: batch=%s single=%d",
      name, tostring(batch[name]), single)
  end
end
check("count_many matches count_all for every view", batch_ok, batch_detail)

check("count_many({}) returns an empty table",
  type(views.count_many({})) == 'table' and vim.tbl_count(views.count_many({})) == 0)

-- =============================================================================
-- Unknown view: same 0/empty contract as #match_all
-- =============================================================================

do
  -- The error notification is expected here; silence it so the test output
  -- stays readable, and restore vim.notify immediately afterwards.
  local real_notify = vim.notify
  vim.notify = function() end                                        -- luacheck: ignore

  local unknown_count = views.count_all('no-such-view')
  local unknown_paths = #views.match_all('no-such-view')
  local unknown_batch = views.count_many({ 'no-such-view' })

  vim.notify = real_notify                                           -- luacheck: ignore

  check("count_all on unknown view counts 0", unknown_count == 0)
  check("match_all on unknown view is empty", unknown_paths == 0)
  check("count_many reports unknown view as 0", unknown_batch['no-such-view'] == 0)
end

-- =============================================================================
-- match_all() ordering is unchanged by the precomputed sort keys
-- =============================================================================

do
  -- Reference: the comparator used before v1.6.1 Ph3, applied to the same
  -- matched set. Both must produce the identical sequence.
  local actual    = views.match_all('t-sort')
  local reference = vim.list_extend({}, actual)
  table.sort(reference, function(a, b)
    return vim.fn.fnamemodify(a, ':t') < vim.fn.fnamemodify(b, ':t')
  end)

  check("sort fixture matched all five notes", #actual == 5,
    string.format("got %d", #actual))

  local same = #actual == #reference
  local first_diff
  for i = 1, math.min(#actual, #reference) do
    if actual[i] ~= reference[i] then
      same = false
      first_diff = first_diff or string.format("index %d: %s ≠ %s", i,
        vim.fn.fnamemodify(actual[i], ':t'), vim.fn.fnamemodify(reference[i], ':t'))
    end
  end
  check("match_all order equals the pre-Ph3 comparator's order", same, first_diff)

  -- Guard the fixture itself: if these names ever stop exercising the
  -- basename-vs-stem difference, the check above stops proving anything.
  local ordered = {}
  for _, p in ipairs(actual) do ordered[#ordered + 1] = vim.fn.fnamemodify(p, ':t:r') end
  local joined = table.concat(ordered, ',')
  check("fixture exercises basename ordering ('sa-b' before 'sa')",
    joined:find('sa%-b,sa,') ~= nil, joined)
end

-- =============================================================================
-- Counts follow the index, with no stale caching
-- =============================================================================

do
  local before = views.count_all('t-alpha')

  local added = write_note('00004_note_alpha_three', { 'alpha' })
  index.invalidate(added)
  check("count_all sees a note added to the view",
    views.count_all('t-alpha') == before + 1,
    string.format("before=%d after=%d", before, views.count_all('t-alpha')))
  check("count_many sees it too",
    views.count_many({ 't-alpha' })['t-alpha'] == before + 1)

  vim.fn.delete(added)
  index.invalidate(added)
  check("count_all sees the note removed", views.count_all('t-alpha') == before,
    string.format("expected %d, got %d", before, views.count_all('t-alpha')))
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
