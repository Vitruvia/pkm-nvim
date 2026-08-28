-- test/test_v1831_p1.lua
-- Tests for v1.83.1 Phase 1: the views-panel count cache.
--
-- The views panel (`<leader>va`) recomputes every view's match count on each
-- open — an O(views × notes) scan. This phase memoizes those counts, keyed by a
-- new index content-generation counter, so a reopen with the corpus unchanged
-- reuses the numbers instead of re-scanning. This test locks:
--   1. index.generation() is monotonic — advances on a content change
--      (invalidate/rebuild), and is STABLE across pure reads (get_all/get,
--      count_many). Reads must never advance it, or the cache never hits.
--   2. count_many stays correct: it agrees with count_all, and its cached path
--      returns the same numbers as a cold compute.
--   3. Cache invalidation by BOTH triggers — a note change (generation bump) and
--      a view-definition change (invalidate() clears the count cache) — is seen
--      by the next count_many.
--
-- Runs against a headless Neovim on the disposable temp root from
-- test/min_init.lua — never the live Notes tree.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1831_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== views count cache (v1.83.1 Ph1) ==")

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

write_note('00001_note_alpha_one', { 'alpha' })
write_note('00002_note_alpha_two', { 'alpha', 'beta' })
write_note('00003_note_beta_one',  { 'beta' })

index.rebuild()

views.save('c-alpha', 'tag:alpha')
views.save('c-beta',  'tag:beta')
views.save('c-empty', 'tag:nothing-matches-this')

local names = { 'c-alpha', 'c-beta', 'c-empty' }

-- =============================================================================
-- 1. generation() is monotonic and read-stable
-- =============================================================================

do
  local g0 = index.generation()
  check("generation() returns a number", type(g0) == 'number')

  -- Pure reads must not advance the generation, or the cache can never hit.
  local _ = index.get_all()
  local _ = views.count_many(names)
  local _ = views.count_many(names)
  check("get_all()/count_many() do not advance the generation",
    index.generation() == g0,
    string.format("g0=%s now=%s", tostring(g0), tostring(index.generation())))

  -- A content change advances it.
  local added = write_note('00004_note_alpha_three', { 'alpha' })
  index.invalidate(added)
  check("invalidate() advances the generation", index.generation() > g0,
    string.format("g0=%s now=%s", tostring(g0), tostring(index.generation())))
  local g1 = index.generation()

  -- rebuild() advances it again.
  index.rebuild()
  check("rebuild() advances the generation", index.generation() > g1)

  -- Clean the extra note so later counts match the 3-note fixture.
  vim.fn.delete(added)
  index.invalidate(added)
end

-- =============================================================================
-- 2. count_many is correct (agrees with count_all), cached path included
-- =============================================================================

do
  local batch = views.count_many(names)
  local ok, detail = true, nil
  for _, name in ipairs(names) do
    local single = views.count_all(name)
    if batch[name] ~= single then
      ok = false
      detail = string.format("%s: batch=%s single=%d", name, tostring(batch[name]), single)
    end
  end
  check("count_many agrees with count_all for every view", ok, detail)

  check("c-alpha counts 2", batch['c-alpha'] == 2, string.format("got %s", tostring(batch['c-alpha'])))
  check("c-beta counts 2",  batch['c-beta']  == 2, string.format("got %s", tostring(batch['c-beta'])))
  check("c-empty counts 0", batch['c-empty'] == 0, string.format("got %s", tostring(batch['c-empty'])))

  -- The cached second call, with no change between, returns the same numbers
  -- and does not advance the generation.
  local g = index.generation()
  local again = views.count_many(names)
  check("cached count_many returns identical numbers",
    again['c-alpha'] == 2 and again['c-beta'] == 2 and again['c-empty'] == 0)
  check("cached count_many did not advance the generation", index.generation() == g)
end

-- =============================================================================
-- 3. Cache invalidation — a note change is seen by the next count_many
-- =============================================================================

do
  local before = views.count_many({ 'c-alpha' })['c-alpha']
  local added  = write_note('00005_note_alpha_four', { 'alpha' })
  index.invalidate(added)
  check("count_many sees a note added to the view (generation bump)",
    views.count_many({ 'c-alpha' })['c-alpha'] == before + 1,
    string.format("before=%d after=%d", before,
      views.count_many({ 'c-alpha' })['c-alpha']))

  vim.fn.delete(added)
  index.invalidate(added)
  check("count_many sees the note removed",
    views.count_many({ 'c-alpha' })['c-alpha'] == before)
end

-- =============================================================================
-- 4. Cache invalidation — a NEW view definition is counted (invalidate clears)
-- =============================================================================

do
  -- Prime the cache at the current generation.
  local _ = views.count_many(names)
  -- Saving a view calls views.invalidate() internally, clearing the count cache
  -- even though the index generation is unchanged (no note moved).
  views.save('c-alpha-beta', 'tag:alpha AND tag:beta')
  local n = views.count_many({ 'c-alpha-beta' })['c-alpha-beta']
  check("a newly-saved view is counted after the cache clears", n == 1,
    string.format("expected 1 (only alpha_two has both), got %s", tostring(n)))
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
