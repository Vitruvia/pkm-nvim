-- test/test_v170_p1.lua
-- Tests for v1.7.0 Phase 1: deep export across the citation graph.
--
-- Exercises the two pure functions (`read_citation_edges`, `collect_deep`)
-- directly, with the identifier→path map injected, so no UI is opened and no
-- folder scan is needed. The traversal semantics under test is the one chosen
-- for this phase: both depths count from the seeds, and a single path may mix
-- directions, spending up to cites_depth `cites` hops and cited_by_depth
-- `cited_by` hops in any order.
--
-- Runs against a real headless Neovim instance on the disposable temp root
-- created by test/min_init.lua — never the live Notes tree.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v170_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== deep export (v1.7.0 Ph1) ==")

local pkm    = require('pkm')
local utils  = require('pkm.utils')
local yaml   = require('pkm.yaml')
local export = require('pkm.export')

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

-- =============================================================================
-- Fixture helpers
-- =============================================================================

--- Build one grouped cites/cited_by value from group → identifier list.
---@param by_group table<string, string[]>
---@return table
local function citation_groups(by_group)
  local out = {}
  for _, group in ipairs({ 'notes', 'bib', 'journal', 'scratch' }) do
    out[group] = {}
    for _, id in ipairs(by_group[group] or {}) do
      out[group][#out[group] + 1] = {
        identifier = id,
        title      = 'Title of ' .. id,
        link       = '[[' .. id .. ']]',
      }
    end
  end
  return out
end

--- Write a note whose cites/cited_by carry the given identifiers.
--- `cites` and `cited_by` are maps of group name → identifier list; a plain
--- array is shorthand for the `notes` group. The frontmatter is rendered with
--- `yaml.generate_yaml`, so the fixture is byte-identical to what the plugin
--- itself writes — including the object-array layout its parser expects.
---@param stem     string
---@param cites    table|nil
---@param cited_by table|nil
---@return string path
local function write_note(stem, cites, cited_by)
  local function normalise(v)
    if v == nil then return {} end
    if v[1] ~= nil then return { notes = v } end
    return v
  end

  local fm_lines = yaml.generate_yaml({
    title    = 'Note ' .. stem,
    tags     = { 'graph' },
    cites    = citation_groups(normalise(cites)),
    cited_by = citation_groups(normalise(cited_by)),
  })

  local lines = { '---' }
  vim.list_extend(lines, fm_lines)
  vim.list_extend(lines, { '---', '', 'Body of ' .. stem })

  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

--- Set of basenames (without extension) from a path list, for order-free
--- comparison against an expected set.
---@param paths string[]
---@return table<string, boolean>, string  set, sorted comma list for messages
local function stems(paths)
  local set, list = {}, {}
  for _, p in ipairs(paths) do
    local stem = vim.fn.fnamemodify(p, ':t:r')
    set[stem]  = true
    list[#list + 1] = stem
  end
  table.sort(list)
  return set, table.concat(list, ',')
end

--- Compare a result path list against an expected set of stems.
---@param paths    string[]
---@param expected string[]
---@return boolean ok, string detail
local function same_set(paths, expected)
  local got, got_str = stems(paths)
  local want = {}
  for _, s in ipairs(expected) do want[s] = true end

  for s in pairs(want) do
    if not got[s] then return false, 'missing ' .. s .. '; got ' .. got_str end
  end
  for s in pairs(got) do
    if not want[s] then return false, 'unexpected ' .. s .. '; got ' .. got_str end
  end
  return true, got_str
end

-- =============================================================================
-- The ROADMAP's worked example
--   1 cites 2, 4, 5   ·   5 cites 7   ·   7 cites 8   ·   1 cited_by 2, 3, 6
-- Default run (cites 2, cited_by 0) must yield {1,2,4,5,7} and not {3,6,8}.
-- =============================================================================

local N = {}
for i = 1, 8 do
  N[i] = string.format('%04d_note_n%d', i, i)
end

local paths_by_id = {}
local function id_of(i) return string.format('note-%04d', i) end

paths_by_id[id_of(1)] = write_note(N[1], { id_of(2), id_of(4), id_of(5) },
                                          { id_of(2), id_of(3), id_of(6) })
paths_by_id[id_of(2)] = write_note(N[2], { id_of(1) }, { id_of(1) })
paths_by_id[id_of(3)] = write_note(N[3], { id_of(1) }, {})
paths_by_id[id_of(4)] = write_note(N[4], {}, { id_of(1) })
paths_by_id[id_of(5)] = write_note(N[5], { id_of(7) }, { id_of(1) })
paths_by_id[id_of(6)] = write_note(N[6], { id_of(1) }, {})
paths_by_id[id_of(7)] = write_note(N[7], { id_of(8) }, { id_of(5) })
paths_by_id[id_of(8)] = write_note(N[8], {}, { id_of(7) })

local items_map = {}
for id, path in pairs(paths_by_id) do items_map[id] = { path = path } end

local seeds = { paths_by_id[id_of(1)] }

do
  local result = export.collect_deep(seeds, { items_map = items_map })
  local ok, detail = same_set(result, { N[1], N[2], N[4], N[5], N[7] })
  check("default 2/0 yields the worked example's {1,2,4,5,7}", ok, detail)
end

do
  local result = export.collect_deep(seeds, { items_map = items_map })
  local got = stems(result)
  check("note 8 (three cites hops) is excluded at depth 2", not got[N[8]])
  check("notes 3 and 6 (citers) are excluded at cited_by 0",
    not got[N[3]] and not got[N[6]])
end

do
  local result = export.collect_deep(seeds,
    { cites_depth = 0, cited_by_depth = 0, items_map = items_map })
  local ok, detail = same_set(result, { N[1] })
  check("depth 0/0 returns the seed alone", ok, detail)
end

do
  local result = export.collect_deep(seeds,
    { cites_depth = 3, cited_by_depth = 0, items_map = items_map })
  local got = stems(result)
  check("depth 3 along cites reaches note 8", got[N[8]] == true)
end

-- =============================================================================
-- cited_by traversal, and the per-path budget that defines this phase
-- =============================================================================

do
  local result = export.collect_deep(seeds,
    { cites_depth = 0, cited_by_depth = 1, items_map = items_map })
  local ok, detail = same_set(result, { N[1], N[2], N[3], N[6] })
  check("cited_by 1 pulls the seed's citers", ok, detail)
end

do
  -- The case that separates this phase's semantics from a pure-direction walk:
  -- note 9 sits one `cited_by` hop past note 4, which is itself one `cites` hop
  -- from the seed. Only a path that mixes directions can reach it.
  --
  --   seed 1 --cites--> 4 <--cites-- 9
  --
  local citer = write_note('0009_note_n9', { id_of(4) }, {})
  items_map[id_of(9)] = { path = citer }
  paths_by_id[id_of(9)] = citer
  -- Rewrite note 4 so it records that citer, making 9 reachable only through
  -- a mixed path: seed 1 --cites--> 4 <--cites-- 9.
  write_note(N[4], {}, { id_of(1), id_of(9) })

  local pure = export.collect_deep(seeds,
    { cites_depth = 1, cited_by_depth = 0, items_map = items_map })
  local pure_set = stems(pure)
  check("with cited_by 0, the mixed-path node is not reached",
    pure_set['0009_note_n9'] == nil)

  local mixed = export.collect_deep(seeds,
    { cites_depth = 1, cited_by_depth = 1, items_map = items_map })
  local mixed_set = stems(mixed)
  check("per-path budget: 1 cites hop + 1 cited_by hop reaches note 9",
    mixed_set['0009_note_n9'] == true)
end

-- =============================================================================
-- Cycles, all four groups, and degenerate inputs
-- =============================================================================

do
  local a = write_note('0011_note_cycle_a', { 'note-0012' }, { 'note-0012' })
  local b = write_note('0012_note_cycle_b', { 'note-0011' }, { 'note-0011' })
  local map = { ['note-0011'] = { path = a }, ['note-0012'] = { path = b } }

  local result = export.collect_deep({ a },
    { cites_depth = 5, cited_by_depth = 5, items_map = map })
  local ok, detail = same_set(result, { '0011_note_cycle_a', '0012_note_cycle_b' })
  check("two-node cycle terminates and yields both notes", ok, detail)
end

do
  local c = write_note('0013_note_cycle_c', { 'note-0014' }, {})
  local d = write_note('0014_note_cycle_d', { 'note-0015' }, {})
  local e = write_note('0015_note_cycle_e', { 'note-0013' }, {})
  local map = {
    ['note-0013'] = { path = c }, ['note-0014'] = { path = d },
    ['note-0015'] = { path = e },
  }
  local result = export.collect_deep({ c },
    { cites_depth = 9, cited_by_depth = 0, items_map = map })
  local ok, detail = same_set(result,
    { '0013_note_cycle_c', '0014_note_cycle_d', '0015_note_cycle_e' })
  check("three-node cycle terminates", ok, detail)
end

do
  -- One edge per citable group: notes, bib, journal, scratch.
  local hub = write_note('0021_note_hub', {
    notes   = { 'note-0022' },
    bib     = { 'bib-0023' },
    journal = { '2026-07-24_10-00-00' },
    scratch = { '2026-07-24_11-00-00' },
  }, {})
  local n  = write_note('0022_note_leaf', {}, {})
  local b  = write_note('0023_bib_leaf',  {}, {})
  local j  = write_note('journal_2026-07-24_10-00-00', {}, {})
  local s  = write_note('scratch_2026-07-24_11-00-00', {}, {})

  local map = {
    ['note-0022']           = { path = n },
    ['bib-0023']            = { path = b },
    ['2026-07-24_10-00-00'] = { path = j },
    ['2026-07-24_11-00-00'] = { path = s },
  }
  local result = export.collect_deep({ hub }, { cites_depth = 1, items_map = map })
  local ok, detail = same_set(result, {
    '0021_note_hub', '0022_note_leaf', '0023_bib_leaf',
    'journal_2026-07-24_10-00-00', 'scratch_2026-07-24_11-00-00',
  })
  check("all four citable groups are traversed", ok, detail)
end

do
  local orphan = write_note('0031_note_dangling', { 'note-9999' }, {})
  local result = export.collect_deep({ orphan },
    { cites_depth = 2, items_map = { ['note-0031'] = { path = orphan } } })
  local ok, detail = same_set(result, { '0031_note_dangling' })
  check("identifier with no file is ignored", ok, detail)
end

do
  local bare = utils.join(notes_dir, '0032_note_no_frontmatter.md')
  vim.fn.writefile({ 'no frontmatter here' }, bare)
  local edges = export.read_citation_edges(bare)
  check("note without frontmatter yields empty edge lists",
    #edges.cites == 0 and #edges.cited_by == 0)

  local missing = export.read_citation_edges(utils.join(notes_dir, 'nope.md'))
  check("unreadable file yields empty edge lists",
    #missing.cites == 0 and #missing.cited_by == 0)

  local result = export.collect_deep({ bare }, { cites_depth = 2, items_map = {} })
  local ok, detail = same_set(result, { '0032_note_no_frontmatter' })
  check("seed without frontmatter still comes back as itself", ok, detail)
end

do
  -- Legacy flat array, as written before the grouped cites/cited_by structure:
  -- the same object-array layout, but hanging directly off cites/cited_by with
  -- no group key in between.
  local legacy   = utils.join(notes_dir, '0033_note_legacy.md')
  local fm_lines = yaml.generate_yaml({
    title    = 'Legacy',
    cites    = { { identifier = 'note-0022', title = 'Leaf', link = '[[0022_note_leaf]]' } },
    cited_by = { { identifier = 'note-0021', title = 'Hub',  link = '[[0021_note_hub]]' } },
  })
  local lines = { '---' }
  vim.list_extend(lines, fm_lines)
  vim.list_extend(lines, { '---', '', 'body' })
  vim.fn.writefile(lines, legacy)

  local edges = export.read_citation_edges(legacy)
  check("legacy flat cites array is read", #edges.cites == 1 and edges.cites[1] == 'note-0022',
    string.format('%d ids', #edges.cites))
  check("legacy flat cited_by array is read",
    #edges.cited_by == 1 and edges.cited_by[1] == 'note-0021')
end

do
  local grouped = export.read_citation_edges(paths_by_id[id_of(1)])
  check("grouped frontmatter is not double-counted",
    #grouped.cites == 3 and #grouped.cited_by == 3,
    string.format('cites=%d cited_by=%d', #grouped.cites, #grouped.cited_by))
end

do
  local result = export.collect_deep({}, { items_map = items_map })
  check("no seeds yields no paths", #result == 0)
end

do
  local a = paths_by_id[id_of(1)]
  local result = export.collect_deep({ a, a }, { cites_depth = 0, items_map = items_map })
  check("duplicate seeds are deduplicated", #result == 1, string.format('got %d', #result))
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
