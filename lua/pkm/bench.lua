-- =============================================================================
-- pkm.bench — Benchmarking and load-testing utilities
-- =============================================================================
-- Dependencies : pkm.utils, pkm.yaml (lazy), pkm.filter (lazy)
-- Consumed by  : developer tooling only — not user-facing, no commands
--
-- All functions print results via vim.notify (INFO level).
-- Run from the Neovim command line:
--   :lua require('pkm.bench').baseline()
--   :lua require('pkm.bench').gen_notes(1000, '/tmp/pkm_bench')
--   :lua require('pkm.bench').run_suite('/tmp/pkm_bench')
--
-- Purpose: establish a measurable baseline of collect_files performance
-- before building index.lua, and validate improvements afterward.
--
-- Public API:
--   time(fn)                  → elapsed_ms (float)
--   gen_notes(n, dest)        → count of files written
--   baseline()                → timed collect_files on real corpus
--   run_suite(bench_dir)      → timed suite at 100 / 1k / 10k synthetic notes
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

-- Tag vocabulary used when generating synthetic notes.
local TAGS = {
  "mathematics", "physics", "biology", "chemistry", "history",
  "philosophy", "literature", "programming", "medicine", "economics",
  "psychology", "linguistics", "logic", "music", "art",
  "rpg", "protocol", "draft", "review", "reference",
}

-- Word pool for title generation.
local WORDS = {
  "Introduction", "Foundations", "Analysis", "Principles", "Theory",
  "Methods", "Overview", "Notes", "Study", "Guide",
  "Review", "Summary", "Concepts", "Applications", "Problems",
}

--- Return a pseudo-random integer in [lo, hi] using math.random.
--- math.randomseed is called once per gen_notes call, not here.
---@param lo integer
---@param hi integer
---@return integer
local function rnd(lo, hi)
  return math.floor(math.random() * (hi - lo + 1)) + lo
end

--- Build a minimal but structurally realistic YAML frontmatter block.
---@param n        integer  Note number (1-based)
---@param tag_list string[] Tags to include in this note
---@param title    string
---@return string  frontmatter text (including --- delimiters and trailing newline)
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
    "---\ntitle: %q\nauthor: \"\"\ncreated_on: \"2025-01-%02d_10-00-00\"\n"
    .. "last_updated_on: \"2025-01-%02d_10-00-00\"\n%s\n"
    .. "cites:\n  notes: []\n  bib: []\n"
    .. "cited_by:\n  notes: []\n  bib: []\n---\n",
    title, (n % 28) + 1, (n % 28) + 1, tags_yaml
  )
end

--- Generate n synthetic .md note files in dest, then return the count written.
--- Files are structured exactly as real PKM consolidated notes, so benchmark
--- results are representative of real collect_files / parse_frontmatter cost.
--- Existing files in dest are overwritten; dest is created if absent.
---@param n    integer  Number of notes to generate
---@param dest string   Destination directory path
---@return integer  count of files written
function M.gen_notes(n, dest)
  vim.fn.mkdir(dest, "p")
  math.randomseed(42)   -- deterministic: same seed → same files every run

  local written = 0
  for i = 1, n do
    -- Pick 0–3 tags pseudo-randomly
    local tag_count = rnd(0, 3)
    local tag_list  = {}
    for _ = 1, tag_count do
      tag_list[#tag_list + 1] = TAGS[rnd(1, #TAGS)]
    end

    -- Build a two-word title
    local title = WORDS[rnd(1, #WORDS)] .. " " .. WORDS[rnd(1, #WORDS)]

    -- Compose filename: 0001_note_Introduction_Foundations.md
    local slug    = title:gsub("%s+", "_")
    local fname   = string.format("%04d_note_%s.md", i, slug)
    local fpath   = utils.join(dest, fname)

    -- Body: a few lines of filler text so text-search benchmarks are realistic
    local body = string.format(
      "\n# %s\n\nThis is synthetic note %d for benchmarking purposes.\n"
      .. "Topic keywords: %s.\n",
      title, i, table.concat(tag_list, ", ")
    )

    local content = make_frontmatter(i, tag_list, title) .. body
    local fh = io.open(fpath, "w")
    if fh then
      fh:write(content)
      fh:close()
      written = written + 1
    end
  end

  vim.notify(
    string.format("PKMBench: wrote %d synthetic notes → %s", written, dest),
    vim.log.levels.INFO)
  return written
end

-- =============================================================================
-- SECTION: collect_files reimplementation (for isolated timing)
-- =============================================================================

--- Replicate the hot path of export.collect_files without any filter short-
--- circuit: read every .md file in dir and parse its frontmatter.
--- Returns the count of files successfully parsed.
--- This is what index.lua will replace with a table lookup.
---@param dir string  Directory to scan
---@return integer parsed
local function scan_and_parse(dir)
  local yaml  = require('pkm.yaml')
  local files = vim.fn.glob(dir .. utils.sep .. "*.md", false, true)
  if type(files) ~= "table" then return 0 end

  local parsed = 0
  for _, path in ipairs(files) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok and lines then
      local fm, _ = yaml.parse_frontmatter(lines)
      if fm then parsed = parsed + 1 end
    end
  end
  return parsed
end

-- =============================================================================
-- SECTION: Baseline — real corpus
-- =============================================================================

--- Time collect_files against the real PKM notes root.
--- Prints elapsed ms and notes/sec. Run this before building index.lua to
--- record the pre-index baseline. Run again after to validate improvement.
---@return number elapsed_ms
function M.baseline()
  local config = require('pkm').config
  if not config then
    vim.notify("PKMBench: PKM not initialised — run require('pkm').setup() first",
      vim.log.levels.ERROR)
    return 0
  end

  local dirs = {
    utils.join(config.root_path, config.folders.consolidated),
    utils.join(config.root_path, config.folders.journal),
    utils.join(config.root_path, config.folders.scratchpad),
  }

  local total_files  = 0
  local elapsed_ms   = M.time(function()
    for _, dir in ipairs(dirs) do
      total_files = total_files + scan_and_parse(dir)
    end
  end)

  local per_note = total_files > 0
    and string.format("%.3f ms/note", elapsed_ms / total_files)
    or  "no notes found"

  vim.notify(string.format(
    "PKMBench baseline: %d notes in %.1f ms  (%s)",
    total_files, elapsed_ms, per_note),
    vim.log.levels.INFO)

  return elapsed_ms
end

-- =============================================================================
-- SECTION: Synthetic suite
-- =============================================================================

--- Run a timed benchmark suite over synthetic note sets of increasing size.
--- Generates notes at 100, 1k, 10k (and 100k if requested) and times
--- scan_and_parse on each. Prints a results table and projects 100k time
--- from the 10k result.
---
--- Usage:
---   -- Standard suite (up to 10k notes):
---   :lua require('pkm.bench').run_suite('/tmp/pkm_bench')
---   -- Extended suite (up to 100k, may take a minute):
---   :lua require('pkm.bench').run_suite('/tmp/pkm_bench', true)
---
---@param bench_dir  string   Directory for synthetic files (will be created)
---@param extended   boolean  If true, also runs the 100k tier (slow)
function M.run_suite(bench_dir, extended)
  local tiers = { 100, 1000, 10000 }
  if extended then tiers[#tiers + 1] = 100000 end

  vim.notify("PKMBench: starting suite in " .. bench_dir, vim.log.levels.INFO)

  local results = {}

  for _, n in ipairs(tiers) do
    local tier_dir = utils.join(bench_dir, tostring(n))

    -- Generate only if the directory doesn't already contain the right count.
    local existing = vim.fn.glob(tier_dir .. utils.sep .. "*.md", false, true)
    if type(existing) ~= "table" or #existing ~= n then
      M.gen_notes(n, tier_dir)
    end

    -- Time it twice and take the second (first run may incur Lua warm-up cost).
    scan_and_parse(tier_dir)  -- warm-up
    local elapsed = M.time(function() scan_and_parse(tier_dir) end)
    local per_note = elapsed / n

    results[#results + 1] = {
      n        = n,
      elapsed  = elapsed,
      per_note = per_note,
    }

    vim.notify(string.format(
      "PKMBench  %6d notes: %7.1f ms  (%.3f ms/note)",
      n, elapsed, per_note),
      vim.log.levels.INFO)
  end

  -- Project 100k from the largest tier measured (linear model).
  local last = results[#results]
  if last and last.n < 100000 then
    local projected = last.per_note * 100000
    vim.notify(string.format(
      "PKMBench  100k projection: ~%.0f ms  (~%.1f s)  [linear from %dk]",
      projected, projected / 1000, last.n / 1000),
      vim.log.levels.INFO)
  end

  vim.notify("PKMBench: suite complete.", vim.log.levels.INFO)
end

return M
