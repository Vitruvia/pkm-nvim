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
--
-- Public API:
--   time(fn)                       → elapsed_ms (float)
--   gen_notes(n, dest)             → count of files written
--   cleanup(bench_dir)             → delete bench_dir and all contents
--   baseline()                     → timed raw scan on real corpus (read-only)
--   run_suite(bench_dir?, opts?)   → four-phase suite; cleans up afterward
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

return M
