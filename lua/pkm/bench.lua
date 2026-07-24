-- =============================================================================
-- pkm.bench — Benchmarking and load-testing utilities
-- =============================================================================
-- Dependencies : pkm.utils, pkm.yaml (lazy), pkm.filter (lazy)
-- Consumed by  : developer tooling only — not user-facing, no commands
--
-- ISOLATION GUARANTEE:
--   - Synthetic files are written to a temporary directory under
--     vim.fn.tempname() unless the caller supplies an explicit bench_dir.
--   - run_suite() deletes all synthetic files after the run by default.
--     Pass opts.keep = true to retain them for manual inspection.
--   - baseline() reads real notes but never writes or modifies any file.
--   - views_open() reads the live index and the live view definitions and
--     writes nothing; in synthetic mode it only touches its own bench_dir.
--   - No function touches files outside its designated bench_dir or the
--     real PKM root (baseline, read-only).
--
-- What each phase measures:
--   Phase 1 — Raw scan   : readfile + parse_frontmatter per file.
--                          Represents the pre-index cost of collect_files.
--                          This is what index.lua eliminates.
--   Phase 2 — Index build: build an in-memory {path → entry} table.
--                          Represents the one-time cost of index.rebuild().
--   Phase 3 — Index query: iterate the already-built table.
--                          Represents post-index get_all() cost (no I/O).
--   Phase 4 — Filter eval: filter.eval() on every entry in the table.
--                          Represents a full filter query after index wiring.
--
-- Phases 2–4 are self-contained simulations inside bench.lua. They do NOT
-- call index.lua or modify the live index, so runs are fully side-effect-free.
--
-- Usage:
--   :lua require('pkm.bench').baseline()
--   :lua require('pkm.bench').run_suite()
--   :lua require('pkm.bench').run_suite(nil, { keep = true })
--   :lua require('pkm.bench').run_suite(nil, { extended = true })
--   :lua require('pkm.bench').cleanup('/some/dir')
--   :lua require('pkm.bench').views_suite()
--   :lua require('pkm.bench').views_suite({ note_count = 1000 })
--   :lua require('pkm.bench').views_open()
--   :lua require('pkm.bench').views_open({ synthetic = 2000 })
--
-- Public API:
--   time(fn)                       → elapsed_ms (float)
--   gen_notes(n, dest)             → count of files written
--   cleanup(bench_dir)             → delete bench_dir and all contents
--   baseline()                     → timed raw scan on real corpus (read-only)
--   run_suite(bench_dir?, opts?)   → four-phase suite; cleans up afterward
--   views_suite(opts?)             → view × note scaling bench (overview scenario)
--   views_open(opts?)              → :PKMViews open-path bench on the live
--                                    corpus and views (read-only), or on a
--                                    synthetic corpus with opts.synthetic
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: Timer
-- =============================================================================

--- Call fn() and return wall-clock elapsed time in milliseconds (float).
--- Uses vim.uv.hrtime() which gives nanosecond resolution.
---@param fn function  Zero-argument function to time
---@return number elapsed_ms
function M.time(fn)
  local t0 = vim.uv.hrtime()
  fn()
  local t1 = vim.uv.hrtime()
  return (t1 - t0) / 1e6   -- nanoseconds → milliseconds
end

-- =============================================================================
-- SECTION: Synthetic note generator
-- =============================================================================

local TAGS = {
  "mathematics", "physics", "biology", "chemistry", "history",
  "philosophy", "literature", "programming", "medicine", "economics",
  "psychology", "linguistics", "logic", "music", "art",
  "rpg", "protocol", "draft", "review", "reference",
}

local WORDS = {
  "Introduction", "Foundations", "Analysis", "Principles", "Theory",
  "Methods", "Overview", "Notes", "Study", "Guide",
  "Review", "Summary", "Concepts", "Applications", "Problems",
}

local function rnd(lo, hi)
  return math.floor(math.random() * (hi - lo + 1)) + lo
end

local function make_frontmatter(n, tag_list, title)
  local tags_yaml
  if #tag_list == 0 then
    tags_yaml = "tags: []"
  else
    local lines = { "tags:" }
    for _, t in ipairs(tag_list) do
      lines[#lines + 1] = "  - " .. t
    end
    tags_yaml = table.concat(lines, "\n")
  end

  return string.format(
    "---\ntitle: %q\nauthor: \"\"\n"
    .. "created_on: \"2025-01-%02d_10-00-00\"\n"
    .. "last_updated_on: \"2025-01-%02d_10-00-00\"\n"
    .. "%s\ncites:\n  notes: []\n  bib: []\n"
    .. "cited_by:\n  notes: []\n  bib: []\n---\n",
    title, (n % 28) + 1, (n % 28) + 1, tags_yaml
  )
end

--- Generate n synthetic .md note files in dest and return the count written.
--- Files replicate real consolidated note structure so benchmarks represent
--- actual parse costs.
--- Existing files in dest are overwritten. dest is created if absent.
--- Callers are responsible for cleanup; use M.cleanup(dest) when done.
---@param n    integer  Number of notes to generate
---@param dest string   Destination directory
---@return integer  count of files written
function M.gen_notes(n, dest)
  vim.fn.mkdir(dest, "p")
  math.randomseed(42)   -- deterministic: same seed → same corpus every run

  local written = 0
  for i = 1, n do
    local tag_count = rnd(0, 3)
    local tag_list  = {}
    for _ = 1, tag_count do
      tag_list[#tag_list + 1] = TAGS[rnd(1, #TAGS)]
    end

    local title = WORDS[rnd(1, #WORDS)] .. " " .. WORDS[rnd(1, #WORDS)]
    local slug  = title:gsub("%s+", "_")
    local fname = string.format("%04d_note_%s.md", i, slug)
    local fpath = utils.join(dest, fname)

    local body = string.format(
      "\n# %s\n\nSynthetic note %d for benchmarking.\nKeywords: %s.\n",
      title, i, table.concat(tag_list, ", ")
    )

    local fh = io.open(fpath, "w")
    if fh then
      fh:write(make_frontmatter(i, tag_list, title) .. body)
      fh:close()
      written = written + 1
    end
  end

  return written
end

-- =============================================================================
-- SECTION: Cleanup
-- =============================================================================

--- Delete bench_dir and all its contents (equivalent to rm -rf).
--- Only operates on the path passed in — never touches the PKM root.
---@param bench_dir string  Directory to remove
function M.cleanup(bench_dir)
  if vim.fn.isdirectory(bench_dir) ~= 1 then return end
  local result = vim.fn.delete(bench_dir, 'rf')
  if result == 0 then
    vim.notify('PKMBench: cleaned up ' .. bench_dir, vim.log.levels.INFO)
  else
    vim.notify('PKMBench: cleanup failed for ' .. bench_dir, vim.log.levels.WARN)
  end
end

-- =============================================================================
-- SECTION: Internal benchmark phases
-- =============================================================================

-- Phase 1: raw scan.
-- readfile + parse_frontmatter for every .md in dir.
-- This is the full pre-index cost that collect_files pays per query.
-- Returns (parsed_count, elapsed_ms).
local function phase_raw_scan(dir)
  local yaml  = require('pkm.yaml')
  local files = vim.fn.glob(dir .. utils.sep .. '*.md', false, true)
  if type(files) ~= 'table' then return 0, 0 end

  local parsed  = 0
  local elapsed = M.time(function()
    for _, path in ipairs(files) do
      local ok, lines = pcall(vim.fn.readfile, path)
      if ok and lines then
        local fm, _ = yaml.parse_frontmatter(lines)
        if fm then parsed = parsed + 1 end
      end
    end
  end)

  return parsed, elapsed
end

-- Phase 2: index build.
-- Read all files and build an in-memory {path → entry} table.
-- Simulates index.rebuild() without touching the live index.
-- Returns (built_table, elapsed_ms).
local function phase_index_build(dir)
  local yaml  = require('pkm.yaml')
  local files = vim.fn.glob(dir .. utils.sep .. '*.md', false, true)
  if type(files) ~= 'table' then return {}, 0 end

  local tbl     = {}
  local elapsed = M.time(function()
    for _, path in ipairs(files) do
      local ok, lines = pcall(vim.fn.readfile, path)
      if ok and lines then
        local fm, content_start = yaml.parse_frontmatter(lines)
        if fm then
          local tags = {}
          if type(fm.tags) == 'table' then
            for _, t in ipairs(fm.tags) do
              if type(t) == 'string' then tags[#tags + 1] = t:lower() end
            end
          end
          local body_parts = {}
          if content_start then
            for i = content_start, #lines do
              body_parts[#body_parts + 1] = lines[i]
            end
          end
          tbl[path] = {
            path  = path,
            title = type(fm.title) == 'string' and fm.title or '',
            tags  = tags,
            body  = table.concat(body_parts, '\n'),
          }
        end
      end
    end
  end)

  return tbl, elapsed
end

-- Phase 3: index query.
-- Iterate an already-built table and collect entries into an array.
-- Simulates index.get_all() on a warm index (no I/O).
-- Returns elapsed_ms.
local function phase_index_query(tbl)
  return M.time(function()
    local out = {}
    for _, entry in pairs(tbl) do
      out[#out + 1] = entry
    end
  end)
end

-- Phase 4: filter eval.
-- Run filter.eval() on every entry in the built table.
-- Uses a moderately selective expression (roughly 3/20 tags match).
-- Returns (match_count, elapsed_ms).
local function phase_filter_eval(tbl)
  local filter = require('pkm.filter')
  local tree, err = filter.parse('tag:mathematics OR tag:physics OR tag:programming')
  if not tree then
    vim.notify('PKMBench: filter parse error: ' .. (err or '?'), vim.log.levels.ERROR)
    return 0, 0
  end

  local matches  = 0
  local elapsed  = M.time(function()
    for _, entry in pairs(tbl) do
      if filter.eval(tree, entry) then
        matches = matches + 1
      end
    end
  end)

  return matches, elapsed
end

-- =============================================================================
-- SECTION: Baseline — real corpus (read-only)
-- =============================================================================

--- Time a raw scan against the real PKM notes root.
--- Reads files but never writes or modifies anything.
--- Run this before wiring index.lua into export.lua to record the baseline
--- on real data. Run again after to validate the improvement.
---@return number elapsed_ms
function M.baseline()
  local config = require('pkm').config
  if not config then
    vim.notify(
      'PKMBench: PKM not initialised — call require("pkm").setup() first',
      vim.log.levels.ERROR)
    return 0
  end

  local dirs = {
    utils.join(config.root_path, config.folders.consolidated),
    utils.join(config.root_path, config.folders.journal),
    utils.join(config.root_path, config.folders.scratchpad),
  }

  local total_files = 0
  local total_ms    = 0

  for _, dir in ipairs(dirs) do
    local n, ms = phase_raw_scan(dir)
    total_files = total_files + n
    total_ms    = total_ms    + ms
  end

  local per_note = total_files > 0
    and string.format('%.3f ms/note', total_ms / total_files)
    or  'no notes found'

  vim.notify(string.format(
    'PKMBench baseline: %d notes in %.1f ms  (%s)',
    total_files, total_ms, per_note),
    vim.log.levels.INFO)

  return total_ms
end

-- =============================================================================
-- SECTION: Synthetic suite
-- =============================================================================

--- Run a four-phase timed benchmark suite over synthetic note sets of
--- increasing size. Synthetic files are deleted after the run unless
--- opts.keep is true.
---
--- Options (opts table):
---   keep     (boolean) keep synthetic files after run; default false
---   extended (boolean) add 100k tier; may take ~30 s; default false
---
--- Output format per tier:
---   PKMBench  N notes | raw Xms  build Xms  query Xms  filter Xms (M matches)
---
---@param bench_dir string|nil  Directory for synthetic files.
---                             Defaults to a unique system temp directory.
---@param opts      table|nil   Option table.
function M.run_suite(bench_dir, opts)
  opts = opts or {}
  local keep     = opts.keep     or false
  local extended = opts.extended or false

  if not bench_dir then
    bench_dir = vim.fn.tempname() .. '_pkmbench'
  end

  local tiers = { 100, 1000, 10000 }
  if extended then tiers[#tiers + 1] = 100000 end

  vim.notify('PKMBench: suite starting', vim.log.levels.INFO)

  for _, n in ipairs(tiers) do
    local tier_dir = utils.join(bench_dir, tostring(n))

    local written = M.gen_notes(n, tier_dir)
    if written ~= n then
      vim.notify(
        string.format('PKMBench: expected %d files, wrote %d — skipping tier', n, written),
        vim.log.levels.WARN)
      goto continue
    end

    -- Warm-up: loads yaml module and JIT-compiles the hot loop. Not reported.
    phase_raw_scan(tier_dir)

    local _, ms1          = phase_raw_scan(tier_dir)
    local tbl, ms2        = phase_index_build(tier_dir)
    local ms3             = phase_index_query(tbl)
    local matches, ms4    = phase_filter_eval(tbl)

    vim.notify(string.format(
      'PKMBench %6d notes | raw %6.1fms  build %6.1fms  query %5.2fms  filter %5.1fms  (%d matches)',
      n, ms1, ms2, ms3, ms4, matches),
      vim.log.levels.INFO)

    ::continue::
  end

  if not extended then
    local tier_10k = utils.join(bench_dir, '10000')
    if vim.fn.isdirectory(tier_10k) == 1 then
      phase_raw_scan(tier_10k)   -- warm-up
      local _, ms = phase_raw_scan(tier_10k)
      local projected = (ms / 10000) * 100000
      vim.notify(string.format(
        'PKMBench  100k projection: ~%.0f ms (~%.1f s) raw scan [linear from 10k]',
        projected, projected / 1000),
        vim.log.levels.INFO)
    end
  end

  if keep then
    vim.notify('PKMBench: files kept at ' .. bench_dir, vim.log.levels.INFO)
  else
    M.cleanup(bench_dir)
  end

  vim.notify('PKMBench: suite complete.', vim.log.levels.INFO)
end

--- Run a timed benchmark for view-hierarchy scaling.
--- Measures how overview-build time (O(V × N)) scales with view count.
--- Uses synthetic notes and filter trees; does not modify live PKM state,
--- views.json, or the live index.
---
--- This is the required measurement gate before introducing any caching of
--- match_all results in sidebar_build_overview or :PKMOrphans. Both call
--- match_all once per defined view (O(V × N) at query time); caching is
--- only justified if this suite shows meaningful latency at realistic V.
---
--- What is measured:
---   single  : one filter evaluated against all N notes
---             (sidebar detail-mode cost: one match_all call per open)
---   overview: V filters evaluated against all N notes, counting only
---             (sidebar_build_overview + :PKMOrphans: one match_all per view)
---
--- Options (opts table):
---   note_count (integer) synthetic notes to generate; default 10000
---   bench_dir  (string)  directory for synthetic files; default temp dir
---   keep       (boolean) retain synthetic files after run; default false
---
---@param opts table|nil
function M.views_suite(opts)
  opts       = opts or {}
  local keep       = opts.keep       or false
  local note_count = opts.note_count or 10000
  local bench_dir  = opts.bench_dir
    or (vim.fn.tempname() .. '_pkmbench_views')

  local filter = require('pkm.filter')

  -- 1. Generate synthetic notes and build an in-memory entry table.
  local notes_dir = utils.join(bench_dir, 'notes')
  vim.notify(
    string.format('PKMBench views: generating %d synthetic notes…', note_count),
    vim.log.levels.INFO)
  M.gen_notes(note_count, notes_dir)

  local tbl, ms_build = phase_index_build(notes_dir)
  local entries = {}
  for _, e in pairs(tbl) do entries[#entries + 1] = e end

  if #entries == 0 then
    vim.notify('PKMBench views: no entries indexed — aborting', vim.log.levels.ERROR)
    if not keep then M.cleanup(bench_dir) end
    return
  end

  vim.notify(string.format(
    'PKMBench views: %d entries indexed in %.1fms',
    #entries, ms_build),
    vim.log.levels.INFO)

  -- 2. Build synthetic filter trees.
  -- Cycles through TAGS to produce distinct single-predicate views, which
  -- approximate typical real-world filter complexity. Subproject AND-chains
  -- at depth D cost ~D× per view; depth-2 chains roughly double the overview
  -- time. Not modelled here: single-predicate filters isolate the eval-loop
  -- cost cleanly as the baseline measurement.
  local function make_trees(n)
    local trees = {}
    for i = 1, n do
      local tag       = TAGS[((i - 1) % #TAGS) + 1]
      local tree, err = filter.parse('tag:' .. tag)
      if tree then
        trees[#trees + 1] = tree
      else
        vim.notify(
          'PKMBench views: parse error: ' .. (err or '?'),
          vim.log.levels.WARN)
      end
    end
    return trees
  end

  -- 3. Warm-up: JIT-compiles the hot eval loop before recording.
  local warm = make_trees(50)
  for _, tree in ipairs(warm) do
    for _, entry in ipairs(entries) do filter.eval(tree, entry) end
  end

  -- 4. Timed runs across view-count tiers.
  local view_counts = { 50, 100, 300, 1000 }

  for _, n_views in ipairs(view_counts) do
    local trees = make_trees(n_views)

    -- Single view: one filter over all entries (sidebar detail-mode cost).
    local ms_single = M.time(function()
      local c = 0
      for _, entry in ipairs(entries) do
        if filter.eval(trees[1], entry) then c = c + 1 end
      end
    end)

    -- Overview: V filters over all entries, counting only.
    -- Mirrors sidebar_build_overview() and :PKMOrphans (both O(V × N)).
    local ms_overview = M.time(function()
      for _, tree in ipairs(trees) do
        local c = 0
        for _, entry in ipairs(entries) do
          if filter.eval(tree, entry) then c = c + 1 end
        end
      end
    end)

    vim.notify(string.format(
      'PKMBench views  %4d views × %5d notes | single %6.2fms  overview %7.1fms  %.2fms/view',
      n_views, #entries, ms_single, ms_overview, ms_overview / n_views),
      vim.log.levels.INFO)
  end

  if keep then
    vim.notify('PKMBench views: files kept at ' .. bench_dir, vim.log.levels.INFO)
  else
    M.cleanup(bench_dir)
  end

  vim.notify('PKMBench views: suite complete.', vim.log.levels.INFO)
end

-- =============================================================================
-- SECTION: Views-open bench
-- =============================================================================
--
-- views_suite() above measures an *idealised* count loop (filter.eval only).
-- The real overview path does more per view: it rebuilds the whole entry array
-- (index.get_all()), materialises a path array, and sorts it. This section
-- prices that real path so an optimisation can be chosen from measurement
-- rather than from inspection.

--- Sort paths in place with the comparator views.match_all() used before
--- v1.6.1 Ph3: one fnamemodify() call per comparison (~N·logN VimL calls).
--- Kept here so the bench can price it against the keyed variant below.
---@param paths string[]  Sorted in place
---@return string[] paths
local function sort_inline(paths)
  table.sort(paths, function(a, b)
    return vim.fn.fnamemodify(a, ':t') < vim.fn.fnamemodify(b, ':t')
  end)
  return paths
end

--- Same ordering, with each key computed once (Schwartzian transform):
--- N fnamemodify() calls instead of ~N·logN.
---@param paths string[]  Sorted in place
---@return string[] paths
local function sort_keyed(paths)
  local key = {}
  for _, p in ipairs(paths) do key[p] = vim.fn.fnamemodify(p, ':t') end
  table.sort(paths, function(a, b) return key[a] < key[b] end)
  return paths
end

--- Emit one aligned result row.
---@param label string
---@param ms    number
---@param note  string|nil  Optional trailing annotation
local function report(label, ms, note)
  vim.notify(string.format(
    'PKMBench views-open  %-26s %9.2f ms%s',
    label, ms, note and ('   ' .. note) or ''),
    vim.log.levels.INFO)
end

--- Synthetic fallback for views_open(): prices the same two shapes
--- (current overview vs count-only) against a disposable temp corpus and
--- in-memory filter trees. Touches no live state and defines no view.
---@param opts table  { synthetic = integer, view_count?, bench_dir?, keep? }
local function views_open_synthetic(opts)
  local note_count = type(opts.synthetic) == 'number' and opts.synthetic or 2000
  local view_count = opts.view_count or 20
  local keep       = opts.keep or false
  local bench_dir  = opts.bench_dir or (vim.fn.tempname() .. '_pkmbench_open')

  local filter    = require('pkm.filter')
  local notes_dir = utils.join(bench_dir, 'notes')

  vim.notify(string.format(
    'PKMBench views-open: generating %d synthetic notes…', note_count),
    vim.log.levels.INFO)
  M.gen_notes(note_count, notes_dir)

  local tbl     = phase_index_build(notes_dir)
  local entries = {}
  for _, e in pairs(tbl) do entries[#entries + 1] = e end

  if #entries == 0 then
    vim.notify('PKMBench views-open: no entries indexed — aborting', vim.log.levels.ERROR)
    if not keep then M.cleanup(bench_dir) end
    return
  end

  local trees = {}
  for i = 1, view_count do
    local tree = filter.parse('tag:' .. TAGS[((i - 1) % #TAGS) + 1])
    if tree then trees[#trees + 1] = tree end
  end

  -- One get_all()-equivalent array rebuild, as index.get_all() performs it.
  local function snapshot()
    local out = {}
    for _, e in ipairs(entries) do out[#out + 1] = e end
    return out
  end

  -- Warm-up: JIT-compiles the eval loop before anything is recorded.
  for _, tree in ipairs(trees) do
    for _, e in ipairs(entries) do filter.eval(tree, e) end
  end

  -- Current shape: per view → array rebuild + path array + sort.
  local ms_current = M.time(function()
    for _, tree in ipairs(trees) do
      local matched = {}
      for _, e in ipairs(snapshot()) do
        if filter.eval(tree, e) then matched[#matched + 1] = e.path end
      end
      sort_inline(matched)
    end
  end)

  -- Count-only shape: one array rebuild for the whole batch, no sort.
  local ms_counts = M.time(function()
    local shared = snapshot()
    for _, tree in ipairs(trees) do
      local c = 0
      for _, e in ipairs(shared) do
        if filter.eval(tree, e) then c = c + 1 end
      end
    end
  end)

  vim.notify(string.format(
    'PKMBench views-open (synthetic): %d views × %d notes',
    #trees, #entries), vim.log.levels.INFO)
  report('overview (current shape)', ms_current, string.format('%.2f ms/view', ms_current / #trees))
  report('overview (count-only)',    ms_counts,  string.format('%.2f ms/view', ms_counts / #trees))

  if keep then
    vim.notify('PKMBench views-open: files kept at ' .. bench_dir, vim.log.levels.INFO)
  else
    M.cleanup(bench_dir)
  end
end

--- Measure the `:PKMViews` / sidebar-overview open path against the corpus and
--- the view definitions this session is configured with. Read-only: it calls
--- the live index and live views but never writes a file or changes any state.
---
--- Point it at a real notes tree through test/min_init.lua's --root flag, which
--- also guarantees the *working tree* copy of the plugin is what gets measured:
---   nvim --headless -u test/min_init.lua -- --root=<notes root> \
---     -c "lua require('pkm.bench').views_open()" -c "qa!"
---
--- Rows reported:
---   index build (cold)      first get_all() when the index was not yet built
---   get_all() warm          one entry-array rebuild — paid once per view today
---   sort N, inline cmp      table.sort over all N paths, fnamemodify per compare
---   sort N, keyed cmp       same ordering, one fnamemodify per path
---   overview (match_all)    #match_all() once per view — today's real cost
---   overview (count_many)   one count_many() for all views, when available
---   detail (largest view)   one match_all() for the view with the most matches
---
--- The two sort rows use all N paths, an upper bound: a single view sorts only
--- its own matches. They isolate the comparator cost, not a per-view total.
---@param opts table|nil  { synthetic = integer } to use a disposable corpus
---                       instead of the live one (see views_open_synthetic)
function M.views_open(opts)
  opts = opts or {}
  if opts.synthetic then
    views_open_synthetic(opts)
    return
  end

  local config = require('pkm').config
  if not config then
    vim.notify(
      'PKMBench: PKM not initialised — call require("pkm").setup() first',
      vim.log.levels.ERROR)
    return
  end

  local index = require('pkm.index')
  local views = require('pkm.views')

  local names = views.list()
  if #names == 0 then
    vim.notify(
      'PKMBench views-open: no views defined for this root — '
      .. 'run views_open({ synthetic = 2000 }) instead',
      vim.log.levels.WARN)
    return
  end

  -- 1. Cold build: only observable on the first index access of a session.
  local ms_cold
  if not index.is_built() then
    ms_cold = M.time(function() index.get_all() end)
  end

  local entries = index.get_all()
  if #entries == 0 then
    vim.notify('PKMBench views-open: index is empty — nothing to measure',
      vim.log.levels.WARN)
    return
  end

  -- 2. Warm-up: JIT-compiles the eval/sort loops before recording.
  for _, name in ipairs(names) do local _ = #views.match_all(name) end

  -- 3. Timed rows.
  local ms_get_all = M.time(function() index.get_all() end)

  local paths = {}
  for _, e in ipairs(entries) do paths[#paths + 1] = e.path end
  local ms_sort_inline = M.time(function() sort_inline(vim.list_extend({}, paths)) end)
  local ms_sort_keyed  = M.time(function() sort_keyed(vim.list_extend({}, paths)) end)

  local counts = {}
  local ms_overview = M.time(function()
    for _, name in ipairs(names) do
      counts[name] = #views.match_all(name)
    end
  end)

  -- Present only after v1.6.1 Ph3 lands; this keeps one bench valid for the
  -- before-and-after comparison without a second pass over this file.
  local ms_count_many
  if type(views.count_many) == 'function' then
    ms_count_many = M.time(function() views.count_many(names) end)
  end

  local largest, largest_count = names[1], -1
  for name, c in pairs(counts) do
    if c > largest_count then largest, largest_count = name, c end
  end
  local ms_detail = M.time(function() views.match_all(largest) end)

  -- 4. Report.
  local v, n = #names, #entries
  vim.notify(string.format(
    'PKMBench views-open: %d views × %d notes  (root: %s)',
    v, n, config.root_path), vim.log.levels.INFO)

  if ms_cold then
    report('index build (cold)', ms_cold, string.format('%.3f ms/note', ms_cold / n))
  else
    report('index build (cold)', 0, 'skipped — index already built')
  end
  report('get_all() warm', ms_get_all, string.format('×%d views today', v))
  report('sort N, inline cmp', ms_sort_inline, string.format('N=%d', n))
  report('sort N, keyed cmp', ms_sort_keyed, string.format('N=%d', n))
  report('overview (match_all)', ms_overview, string.format('%.2f ms/view', ms_overview / v))
  if ms_count_many then
    report('overview (count_many)', ms_count_many, string.format('%.2f ms/view', ms_count_many / v))
  else
    report('overview (count_many)', 0, 'n/a — count_many() not present yet')
  end
  report('detail (largest view)', ms_detail,
    string.format("'%s', %d matches", largest, largest_count))
end

return M
