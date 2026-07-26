-- test/test_v181_p3.lua
-- Tests for v1.8.1 Phase 3: `u` lands on the edit, not on the timestamp.
--
-- The bug has been "fixed" three times and keeps coming back, which is the
-- symptom of fixing without a reproduction. So this file is the reproduction
-- first and the regression test second: it edits a body line, writes, undoes,
-- and asks only one question — where is the cursor.
--
-- Two writers can move it. BufWritePre rewrites last_updated_on in the
-- frontmatter and joins that into the user's undo block; BufWritePost replaces
-- the whole buffer with what is on disk and joins that too. Undo restores the
-- position of the *last* mutation in the block, so either can win.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v181_p3.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== the undo cursor (v1.8.1 Ph3) ==")

local pkm   = require('pkm')
local utils = require('pkm.utils')

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

--- A note with a real frontmatter block and a body long enough that the
--- frontmatter lines and the edited line cannot be confused.
---@param stem string
---@return string path
local function write_note(stem)
  local lines = {
    '---',
    'title: ' .. stem,
    'type: note',
    'created_on: 2026-07-01T10:00:00',
    'last_updated_on: 2026-07-01T10:00:00',
    'tags: []',
    '---',
    '',
    'primeira linha do corpo',
    'segunda linha do corpo',
    'terceira linha do corpo',
    'quarta linha do corpo',
  }
  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

---@param key string
local function feed(key)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, false, true), 'x', false)
end

--- Where is `last_updated_on` in the current buffer?
---@return integer|nil lnum
local function timestamp_line()
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:match('^last_updated_on:') then return i end
    if i > 20 then break end
  end
  return nil
end

-- =============================================================================
-- Edit a body line, save, undo
-- =============================================================================

do
  local path = write_note('3101_note_Undo')
  vim.cmd('edit ' .. vim.fn.fnameescape(path))

  local target = 10   -- 'segunda linha do corpo'
  vim.api.nvim_win_set_cursor(0, { target, 0 })
  feed('A  editado<Esc>')

  local after_edit = vim.api.nvim_win_get_cursor(0)[1]
  check("the edit happened on the line we aimed at", after_edit == target,
    string.format('cursor on %d, expected %d', after_edit, target))
  check("and the line carries the edit",
    (vim.api.nvim_buf_get_lines(0, target - 1, target, false)[1] or '')
      :find('editado', 1, true) ~= nil)

  vim.cmd('write')
  -- BufWritePost does its work from vim.schedule, so the buffer is not settled
  -- when :write returns.
  vim.wait(1000, function() return false end, 20)

  local ts = timestamp_line()
  check("the write refreshed last_updated_on", ts ~= nil, 'no timestamp line')

  feed('u')
  local landed = vim.api.nvim_win_get_cursor(0)[1]

  check("undo puts the cursor back on the edited line", landed == target,
    string.format('landed on %d (edit %d, timestamp %s)',
      landed, target, tostring(ts)))
  check("and not in the frontmatter", ts == nil or landed > ts,
    string.format('landed on %d, timestamp on %s', landed, tostring(ts)))
  check("one undo is enough to remove the edit",
    (vim.api.nvim_buf_get_lines(0, target - 1, target, false)[1] or '')
      :find('editado', 1, true) == nil,
    vim.api.nvim_buf_get_lines(0, target - 1, target, false)[1] or '')
end

-- =============================================================================
-- The same, from a second window on the same buffer
-- =============================================================================
--
-- BufWritePost restores the view inside nvim_buf_call, which does not
-- guarantee it runs in the window the user is looking at. With the buffer in
-- two windows, a save/restore aimed at the wrong one shows up here.

do
  local path = write_note('3102_note_Undo2')
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  vim.cmd('split')

  local target = 11   -- 'terceira linha do corpo'
  vim.api.nvim_win_set_cursor(0, { target, 0 })
  feed('A  editado<Esc>')
  vim.cmd('write')
  vim.wait(1000, function() return false end, 20)

  feed('u')
  local landed = vim.api.nvim_win_get_cursor(0)[1]
  check("undo lands on the edit with the buffer in two windows",
    landed == target,
    string.format('landed on %d, expected %d', landed, target))

  vim.cmd('only')
end

-- =============================================================================
-- Steady state: the note is already normalised
-- =============================================================================
--
-- The first save of a fresh note expands its frontmatter (the cites/cited_by
-- blocks are created), so the buffer legitimately changes. Every save after
-- that changes nothing, and this is the case real editing lives in.

do
  local path = write_note('3103_note_Rotina')
  vim.cmd('edit ' .. vim.fn.fnameescape(path))

  -- First save: normalise, and let the reload settle.
  vim.cmd('write')
  vim.wait(1000, function() return false end, 20)

  local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local target = #before - 1
  vim.api.nvim_win_set_cursor(0, { target, 0 })
  feed('A  outra vez<Esc>')
  vim.cmd('write')
  vim.wait(1000, function() return false end, 20)

  local landed_before = vim.api.nvim_win_get_cursor(0)[1]
  check("saving an already-normalised note leaves the cursor alone",
    landed_before == target,
    string.format('cursor on %d, expected %d', landed_before, target))

  feed('u')
  local landed = vim.api.nvim_win_get_cursor(0)[1]
  check("and undo lands on the edit, not in the frontmatter", landed == target,
    string.format('landed on %d, expected %d', landed, target))
end

-- =============================================================================
-- The stamp itself: written on release, and only when the note was saved
-- =============================================================================

---@param path string
---@return string|nil
local function stamp_of(path)
  for i, line in ipairs(vim.fn.readfile(path)) do
    local v = line:match('^last_updated_on:%s*(.+)$')
    if v then return (v:gsub('^"(.*)"$', '%1')) end
    if line == '---' and i > 1 then break end
  end
  return nil
end

do
  local path = write_note('3104_note_Carimbo')
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local bufnr = vim.api.nvim_get_current_buf()
  local original = stamp_of(path)

  vim.api.nvim_win_set_cursor(0, { 10, 0 })
  feed('A  mudado<Esc>')
  vim.cmd('write')
  vim.wait(500, function() return false end, 20)

  check("the frontmatter is untouched while the note is open",
    stamp_of(path) == original,
    string.format('%s vs %s', tostring(stamp_of(path)), tostring(original)))

  vim.cmd('bdelete! ' .. bufnr)
  vim.wait(500, function() return false end, 20)

  check("releasing a saved note stamps it on disk",
    stamp_of(path) ~= nil and stamp_of(path) ~= original,
    string.format('%s vs %s', tostring(stamp_of(path)), tostring(original)))
end

do
  -- A note merely opened and closed is not an edit, and must not be stamped.
  local path = write_note('3105_note_SoLeitura')
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local bufnr = vim.api.nvim_get_current_buf()
  local original = stamp_of(path)

  vim.cmd('bdelete! ' .. bufnr)
  vim.wait(500, function() return false end, 20)

  check("opening and closing a note without saving leaves it alone",
    stamp_of(path) == original,
    string.format('%s vs %s', tostring(stamp_of(path)), tostring(original)))
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
