-- test/test_v1820_p1.lua
-- Tests for v1.82.0 Phase 1: membership WRITES resolve against a view's OWN
-- filter, not the v1.81.0 containment roll-up.
--
-- The bug this guards (the 2026-08-19 gestor `_meta` reorg): under containment,
-- get_tree(parent) = own filter OR the union of every child. Adding a note "to
-- the parent" was resolved from that composed tree, so it offered the SUBVIEWS'
-- tags as ways to satisfy the parent — "add to _meta" proposed the `editais` /
-- `guia-estudos` child tags instead of _meta's own `concursos-_meta`. Reads must
-- still compose downward (a parent CONTAINS its children); only the WRITE side
-- (set_membership / view_flow / new_note_in_view) must use the OWN filter.
--
-- Runs against the disposable temp root from test/min_init.lua — never the live
-- Notes tree.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1820_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== membership writes use the OWN filter (v1.82.0 Ph1) ==")

local pkm    = require('pkm')
local utils  = require('pkm.utils')
local index  = require('pkm.index')
local views  = require('pkm.views')
local tags   = require('pkm.tags')
local filter = require('pkm.filter')

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

--- Write one fixture note and return its absolute path.
local function write_note(stem, note_tags)
  local lines = { '---', string.format('title: "%s"', stem), 'tags:' }
  for _, t in ipairs(note_tags) do lines[#lines + 1] = '  - ' .. t end
  lines[#lines + 1] = '---'
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'body of ' .. stem
  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

local function tags_of(path)
  index.invalidate(path)
  local entry = index.get(path)
  return (entry and entry.tags) or {}
end

--- Count index entries a parsed tree matches (mirrors match_all's core).
local function count_tree(tree)
  local n = 0
  for _, e in ipairs(index.get_all()) do
    if filter.eval(tree, e) then n = n + 1 end
  end
  return n
end

-- Fixture: a CONTAINER view with a single clean own tag, and a child that
-- filters on a DIFFERENT tag — the shape `_meta` should have had.
local n_own   = write_note('1000_note_own',   { 'meta-own' })
local n_child = write_note('1001_note_child', { 'child-tag' })
local n_plain = write_note('1002_note_plain', { 'unrelated' })
index.rebuild()

views.save('t-container', 'tag:meta-own')
views.save_subproject('t-sub', 't-container', 'tag:child-tag')

-- =============================================================================
-- Reads still compose downward; the own filter does not.
-- =============================================================================

do
  local composed = views.get_tree('t-container')
  local own      = views.get_own_tree('t-container')
  check("get_tree composes the child in (own OR child = 2)",
    count_tree(composed) == 2, tostring(count_tree(composed)))
  check("get_own_tree stays on the own filter (meta-own = 1)",
    count_tree(own) == 1, tostring(count_tree(own)))
  check("the own filter matches the own-tag note",
    filter.eval(own, index.get(n_own)))
  check("the own filter does NOT match the child-tag note",
    not filter.eval(own, index.get(n_child)))
end

-- =============================================================================
-- set_membership(add) writes the parent's OWN tag, unambiguously — the direct
-- regression. Before the fix the composed tree offered {meta-own} vs {child-tag}
-- and set_membership refused with "several ways"; now the own filter is the one
-- unambiguous answer.
-- =============================================================================

do
  local ok, err = views.set_membership(n_plain, 't-container', 'add')
  check("add to the container succeeds (not 'several ways')", ok, tostring(err))

  local t = tags_of(n_plain)
  check("it wrote the container's own tag", vim.tbl_contains(t, 'meta-own'),
    table.concat(t, ','))
  check("and NOT a child's tag", not vim.tbl_contains(t, 'child-tag'),
    table.concat(t, ','))
  check("the note is now a DIRECT member (own filter matches it)",
    filter.eval(views.get_own_tree('t-container'), index.get(n_plain)))
end

-- =============================================================================
-- new_note_in_view seeds the OWN tag too (no picker: one unambiguous alternative).
-- =============================================================================

do
  local done = false
  local orig_notify, orig_select = vim.notify, vim.ui.select
  local orig_input = vim.fn.input
  vim.notify    = function() end                                    -- luacheck: ignore
  vim.ui.select = function(items, _, on_choice) on_choice(items[1], 1) end
  vim.fn.input  = function() return 'Nascida No Container' end

  tags.new_note_in_view('t-container', { on_done = function() done = true end })
  vim.wait(2000, function() return done end, 20)

  vim.notify, vim.ui.select, vim.fn.input = orig_notify, orig_select, orig_input

  local opened = vim.api.nvim_buf_get_name(0)
  local t = (opened ~= '' and opened:match('%.md$')) and tags_of(opened) or {}
  check("a note born in the container carries the own tag",
    vim.tbl_contains(t, 'meta-own'), table.concat(t, ','))
  check("and not a child's tag", not vim.tbl_contains(t, 'child-tag'),
    table.concat(t, ','))
end

-- =============================================================================
-- Removal is direct too: it strips the OWN membership; a note that is in the
-- container only via a child stays in it (containment), and removing the parent
-- does not touch the child's tag.
-- =============================================================================

do
  local ok, err = views.set_membership(n_own, 't-container', 'remove')
  check("remove from the container succeeds", ok, tostring(err))
  check("the own tag was stripped", not vim.tbl_contains(tags_of(n_own), 'meta-own'),
    table.concat(tags_of(n_own), ','))

  -- The child note never had meta-own; removing the parent's membership leaves
  -- the child-tag note untouched, and it is still IN the container via roll-up.
  check("the child-tag note keeps its own tag",
    vim.tbl_contains(tags_of(n_child), 'child-tag'))
  check("and is still contained by the parent (get_tree still matches it)",
    filter.eval(views.get_tree('t-container'), index.get(n_child)))
end

-- =============================================================================
-- get_own_tree error contract mirrors get_tree for an unknown view.
-- =============================================================================

do
  local tree, err = views.get_own_tree('no-such-view')
  check("get_own_tree on an unknown view returns nil + error",
    tree == nil and type(err) == 'string' and err:find('no view named', 1, true) ~= nil,
    tostring(err))
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
