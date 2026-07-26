-- test/test_v181_p2.lua
-- Tests for v1.8.1 Phase 2: every removal confirms.
--
-- The rule is a whole-plugin one (doc/PRINCIPLES.md), and most of the audit it
-- came from found paths that already confirmed. One did not: `D` in the buffer
-- panel ran `bdelete!` straight through, so unsaved edits vanished without a
-- word — the entire difference between it and `d`.
--
-- What is asserted here is the shape the rule requires: the question is asked
-- only when something is at stake, answering "no" changes nothing, and
-- answering "yes" does exactly what it said.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v181_p2.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== every removal confirms (v1.8.1 Ph2) ==")

local pkm   = require('pkm')
local utils = require('pkm.utils')
local ui    = require('pkm.ui')

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

--- The buffer panel's window, or nil. `panel.create{ name = 'bufpanel' }`
--- stamps its buffer with this filetype and leaves it unnamed, so the filetype
--- is what identifies it.
---@return integer|nil win
local function panel_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_get_option_value('filetype', { buf = buf }) == 'pkm-bufpanel' then
      return w
    end
  end
  return nil
end

--- Open a note, optionally leaving unsaved edits in it.
---@param stem     string
---@param modified boolean
---@return integer bufnr
local function open_note(stem, modified)
  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile({ '---', 'title: ' .. stem, '---', '', 'corpo' }, path)

  -- Panel windows set `winfixbuf`, so editing must happen somewhere else —
  -- the same reason the plugin routes its own opens through focus_main_win().
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(w)
    if not vim.api.nvim_get_option_value('filetype', { buf = buf }):match('^pkm%-') then
      vim.api.nvim_set_current_win(w)
      break
    end
  end

  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local bufnr = vim.api.nvim_get_current_buf()
  if modified then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'linha nova' })
  end
  return bufnr
end

--- Put the buffer panel's cursor on `bufnr`'s row and press `key` there.
--- Returns false when the panel has no row for that buffer.
---@param bufnr integer
---@param key   string
---@return boolean
local function press_on(bufnr, key)
  -- PKM mode opens the panel on its own, so asking the window list is more
  -- reliable than asking whether we opened it.
  if not panel_win() then ui.toggle_bufpanel() end
  vim.wait(500, function() return panel_win() ~= nil end, 10)

  local win = panel_win()
  if not win then return false end
  ui.refresh_bufpanel()
  vim.wait(100, function() return false end, 10)

  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
  -- The panel renders the stem, not the filename: `:t:r`, not `:t`.
  local want  = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t:r')
  for i, line in ipairs(lines) do
    if line:find(want, 1, true) then
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_win_set_cursor(win, { i, 0 })
      vim.api.nvim_feedkeys(key, 'x', false)
      return true
    end
  end
  return false
end

-- =============================================================================
-- The force key asks only when it would cost something
-- =============================================================================

do
  -- A saved buffer: force-closing it loses nothing, so nothing is asked. The
  -- rule guards the irreversible, it does not tax every keystroke.
  local asked = false
  local orig  = vim.fn.confirm
  vim.fn.confirm = function() asked = true return 2 end

  local bufnr = open_note('2101_note_Salva', false)
  local found = press_on(bufnr, 'D')
  vim.fn.confirm = orig

  check("the buffer panel lists the note", found, 'row not found')
  check("force-closing a saved buffer asks nothing", asked == false)
  -- `bdelete` unloads and unlists; it does not invalidate the handle, so
  -- "closed" is `is_loaded`, not `is_valid`.
  check("and the buffer is closed", not vim.api.nvim_buf_is_loaded(bufnr))
end

--- Carried between the two halves of the modified-buffer case: cancelling then
--- discarding has to act on the same buffer for the pair to mean anything.
local dirty_buf

do
  -- A modified buffer: this is the case that used to lose work silently.
  local asked, message = false, nil
  local orig = vim.fn.confirm
  vim.fn.confirm = function(msg)
    asked, message = true, msg
    return 2  -- Cancel
  end

  local bufnr = open_note('2102_note_Suja', true)
  dirty_buf   = bufnr
  local found = press_on(bufnr, 'D')
  vim.fn.confirm = orig

  check("the buffer panel lists the modified note", found, 'row not found')
  check("force-closing an unsaved buffer asks first", asked)
  check("and the question states what is lost, not that it is dangerous",
    message ~= nil and message:find('unsaved changes', 1, true) ~= nil,
    tostring(message))
  check("answering no keeps the buffer", vim.api.nvim_buf_is_loaded(bufnr))
  check("with its edits intact",
    vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified)
end

do
  -- Answering yes does exactly what it said it would.
  local orig = vim.fn.confirm
  vim.fn.confirm = function() return 1 end  -- Discard

  local found = press_on(dirty_buf, 'D')
  vim.fn.confirm = orig

  check("the modified note is still listed", found, 'row not found')
  check("answering discard closes it", not vim.api.nvim_buf_is_loaded(dirty_buf))
end

-- =============================================================================
-- The gentler key still offers to save
-- =============================================================================

do
  -- `d` was already correct; it is asserted here so the pair stays a pair.
  local asked = false
  local orig  = vim.fn.confirm
  vim.fn.confirm = function() asked = true return 3 end  -- Cancel

  local bufnr = open_note('2103_note_Outra', true)
  local found = press_on(bufnr, 'd')
  vim.fn.confirm = orig

  check("closing an unsaved buffer with d asks too", found and asked)
  check("and cancelling keeps it", vim.api.nvim_buf_is_loaded(bufnr))
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
