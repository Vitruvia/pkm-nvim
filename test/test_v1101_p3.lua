-- test/test_v1101_p3.lua
-- Tests for v1.10.1 Phase 3: the two costs that were measured and left.
--
--   1. `:PKMOrphans` was O(V × N) at call time. It asked `views.match_all`
--      once per view, so it read the index V times and paid V sorts — a
--      basename ordering it then threw away, since all it does with the
--      result is test membership. `views.match_set` is the batch, unordered
--      counterpart of `count_many`: one index read, V filter passes, a set.
--
--   2. `bench.lua` joined a caller-supplied `bench_dir` with the *native*
--      separator, so a Unix-style dir on Windows produced mixed paths. Note
--      what that does and does not break: the files come out right either
--      way, because mkdir and glob both accept mixed separators. So the
--      check below is on the resolved string, not on the files — a test that
--      created files and found them would pass with the bug still in place.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1101_p3.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

local pkm   = require('pkm')
local utils = require('pkm.utils')
local views = require('pkm.views')
local index = require('pkm.index')

-- =============================================================================
-- Fixture: five notes whose view membership is known by construction
-- =============================================================================

local dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(dir, 'p')

---@param name  string
---@param tags  string[]
---@param cites string[]  filenames this note cites (drives has_citations)
---@return string path
local function make_note(name, tags, cites)
  local lines = {
    '---', 'title: ' .. name, 'author: ""',
  }
  -- Block form, not `tags: [a, b]`: pkm.yaml does not parse a flow sequence,
  -- it keeps it as the literal string. A fixture written the other way gives
  -- every note zero tags, which is silent — see the control below.
  if #tags == 0 then
    lines[#lines + 1] = 'tags: []'
  else
    lines[#lines + 1] = 'tags:'
    for _, t in ipairs(tags) do lines[#lines + 1] = '  - ' .. t end
  end
  vim.list_extend(lines, {
    'created_on: "2026-07-27T10:00:00"', 'last_updated_on: "2026-07-27T10:00:00"',
    'cites:', '  notes:',
  })
  for _, c in ipairs(cites) do lines[#lines + 1] = '    - ' .. c end
  if #cites == 0 then lines[#lines] = '  notes: []' end
  vim.list_extend(lines, {
    '  bib: []', '  journal: []', '  scratch: []',
    'cited_by:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    '---', '', 'corpo de ' .. name,
  })
  local path = utils.join(dir, name)
  vim.fn.writefile(lines, path)
  return path
end

local p_rpg   = make_note('9001_note_p3_rpg.md',   { 'p3rpg' },            {})
local p_math  = make_note('9002_note_p3_math.md',  { 'p3math' },           {})
local p_both  = make_note('9003_note_p3_both.md',  { 'p3rpg', 'p3math' },  {})
local p_orph  = make_note('9004_note_p3_orphan.md', {},                    {})
local p_cited = make_note('9005_note_p3_cited.md', {}, { '9001_note_p3_rpg' })

index.rebuild()

views.save('__p3_view_rpg',  'tag:p3rpg')
views.save('__p3_view_math', 'tag:p3math')

-- =============================================================================
-- match_set: the union of the same views match_all reports, and nothing else
-- =============================================================================

print("== views.match_set ==")

local names = { '__p3_view_rpg', '__p3_view_math' }

-- Control. An empty set agrees with an empty set, so the equivalence below
-- would pass on a fixture whose tags never parsed — which is exactly what the
-- first draft of this file did. Assert the views match something first.
check("control: the fixture's views match notes at all",
  #views.match_all('__p3_view_rpg') == 2 and #views.match_all('__p3_view_math') == 2,
  string.format('rpg=%d math=%d',
    #views.match_all('__p3_view_rpg'), #views.match_all('__p3_view_math')))

-- The independent answer: built from match_all, the function match_set is
-- meant to replace. Two views that match *different* notes, so a set that
-- dropped one view (or intersected instead of uniting) cannot agree by luck.
local expected = {}
for _, n in ipairs(names) do
  for _, p in ipairs(views.match_all(n)) do expected[utils.normalize(p)] = true end
end

local got = views.match_set(names)

local same, extra, missing = true, nil, nil
for p in pairs(expected) do if not got[p] then same, missing = false, p end end
for p in pairs(got) do if not expected[p] then same, extra = false, p end end

check("agrees with the union of match_all over the same views", same,
  'missing=' .. tostring(missing) .. ' extra=' .. tostring(extra))

local function count(set)
  local c = 0
  for _ in pairs(set) do c = c + 1 end
  return c
end

-- Three distinct notes, not four: the note in both views appears once. If the
-- union were being built by concatenation this count would be 4.
check("the note in two views is counted once", count(got) == 3, 'n=' .. count(got))
check("the rpg-only note is in the set",  got[utils.normalize(p_rpg)]  == true)
check("the math-only note is in the set", got[utils.normalize(p_math)] == true)
check("the note in both views is in the set", got[utils.normalize(p_both)] == true)
check("the note in no view is absent",   got[utils.normalize(p_orph)]  == nil)
check("the untagged but cited note is absent", got[utils.normalize(p_cited)] == nil)

-- Keys are normalized, which is the contract the membership test depends on.
local foreign = utils.is_windows and '/' or '\\'
local all_native = true
for p in pairs(got) do if p:find(foreign, 1, true) then all_native = false end end
check("every key is in the platform's own separator", all_native,
  'a key still contains ' .. foreign)

-- Error behaviour matches match_all's: notify and contribute nothing, while
-- the valid views in the same batch are still honoured.
local mixed = views.match_set({ '__p3_view_rpg', '__p3_nonexistent_view__' })
check("an unknown view contributes nothing", count(mixed) == 2, 'n=' .. count(mixed))
check("and the valid view in the same batch still counts",
  mixed[utils.normalize(p_rpg)] == true and mixed[utils.normalize(p_both)] == true)

check("no views at all yields an empty set", count(views.match_set({})) == 0)

-- =============================================================================
-- The caller: :PKMOrphans still names exactly the orphan
-- =============================================================================

print("\n== :PKMOrphans over the same fixture ==")

-- An orphan has no tags, no citations, and belongs to no view — the command's
-- own definition, recomputed here against the set match_set returns.
local viewed = views.match_set(views.list())
local orphans = {}
for _, e in ipairs(index.get_all()) do
  if (not e.has_citations) and (#(e.tags or {}) == 0)
    and (not viewed[utils.normalize(e.path)]) then
    orphans[#orphans + 1] = utils.normalize(e.path)
  end
end

check("exactly one orphan in the fixture", #orphans == 1,
  'found ' .. #orphans .. ': ' .. table.concat(orphans, ', '))
check("and it is the untagged, uncited, unviewed note",
  orphans[1] == utils.normalize(p_orph), tostring(orphans[1]))

-- The command itself is deliberately not invoked here: with no Telescope it
-- falls back to `ui.browse_paths`, whose `inputlist` waits for a keypress and
-- hangs a headless run. What the command adds over the loop above is the
-- picker, and a picker is what the smoke note is for.
check("the command is registered",
  vim.fn.exists(':PKMBrowse') == 2, tostring(vim.fn.exists(':PKMBrowse')))

-- =============================================================================
-- bench: the resolved directory is in one separator
-- =============================================================================

print("\n== bench._resolve_bench_dir ==")

local bench = require('pkm.bench')

-- What a developer would type on either platform: the *other* platform's
-- separator. Before the fix this came back untouched and utils.join then
-- appended the native one, mixing the two in every derived path.
local supplied = utils.is_windows and '/tmp/pkm_bench' or 'C:\\tmp\\pkm_bench'
local resolved = bench._resolve_bench_dir(supplied, '_unused')

check("the foreign separator does not survive",
  not resolved:find(foreign, 1, true), resolved)
check("the path components are preserved",
  resolved:find('pkm_bench', 1, true) ~= nil, resolved)
check("joining onto it does not reintroduce a mix",
  not utils.join(resolved, 'notes'):find(foreign, 1, true),
  utils.join(resolved, 'notes'))

-- The fallback path: no dir supplied, so one is generated with the suffix.
local generated = bench._resolve_bench_dir(nil, '_pkmbench_p3')
check("the generated fallback carries its suffix",
  generated:find('_pkmbench_p3', 1, true) ~= nil, generated)
check("and the generated fallback is native too",
  not generated:find(foreign, 1, true), generated)

-- =============================================================================
-- Cleanup: the scratch views. The notes live in min_init's disposable root.
-- =============================================================================

views.delete('__p3_view_rpg')
views.delete('__p3_view_math')

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
