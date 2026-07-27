-- test/test_v1101_p1.lua
-- Tests for v1.10.1 Phase 1: a note is prose, so its text is not configuration.
--
-- A line like "um exemplo ex: Será" is a Vim modeline: text, whitespace, the
-- `ex:` marker, then what Vim reads as an option name. Opening or saving such a
-- note raised E518. Two separate triggers had to be closed:
--
--   1. Neovim applies modelines when it reads the file (`:edit`).
--   2. PKM re-fired them on every save, because `:doautocmd` applies modelines
--      unless given `<nomodeline>` — and the Syntax refire in BufWritePost did
--      not give it.
--
-- The control below is the point of the file: it proves modelines are *on* in
-- this session and would fire, so the notes' immunity is PKM's doing and not an
-- accident of the test environment.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1101_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== notes are prose, not configuration (v1.10.1 Ph1) ==")

local pkm = require('pkm')

-- =============================================================================
-- Control: modelines are on, and they fire outside the PKM root
-- =============================================================================

-- `numberwidth`, not `shiftwidth`, and the smoke pass is what taught the
-- difference. Neovim's own markdown ftplugin ends with
--   setlocal expandtab tabstop=4 softtabstop=4 shiftwidth=4
-- and it runs *after* the modeline, so on a real session `shiftwidth` reports
-- 4 from markdown.vim whether or not the modeline fired: the expected value
-- and the unexpected one both arrive from the wrong author. `numberwidth` is
-- touched by no ftplugin, so it answers the question actually being asked —
-- did the modeline apply. Verified: same buffer, same moment, nuw=7 sourced
-- from the modeline while sw=4 is sourced from markdown.vim.
local outside = vim.fn.tempname() .. '.md'
vim.fn.writefile({ '# fora do vault', '', 'texto', '', 'um exemplo vim: nuw=7' }, outside)
vim.cmd('edit ' .. vim.fn.fnameescape(outside))

local function nuw_source()
  return (vim.fn.execute('verbose set numberwidth?'):match('Last set from ([^\n]*)') or '')
end

-- vim.go, not vim.o: 'modeline' is local to buffer, so vim.o reports the
-- current buffer's effective value — which is exactly what PKM turns off.
check("modelines are enabled in this session at all",
  vim.go.modeline == true, tostring(vim.go.modeline))
check("and they fire on a file outside the PKM root",
  vim.wo.numberwidth == 7, tostring(vim.wo.numberwidth))
check("and the source Vim reports for it is the modeline",
  nuw_source():find('modeline', 1, true) ~= nil, nuw_source())

vim.cmd('bwipeout!')

-- =============================================================================
-- A note under the root is immune, on read and on write
-- =============================================================================

local dir = pkm.config.root_path .. '/03-Consolidated'
vim.fn.mkdir(dir, 'p')

---@param name string
---@param last string  the body line that looks like a modeline
---@return string path
local function make_note(name, last)
  local path = dir .. '/' .. name
  vim.fn.writefile({
    '---', 'title: ' .. name, 'author: ""', 'tags: []',
    'created_on: "2026-07-26T20:00:00"', 'last_updated_on: "2026-07-26T20:00:00"',
    'cites:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    'cited_by:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    '---', '', 'corpo da nota', '', last,
  }, path)
  return path
end

-- A real option rather than a bogus one: a wrong option name proves only that
-- an error was raised, while a real one proves whether the modeline was
-- *applied*. `numberwidth` for the reason given at the control above.
local applied = make_note('0001_note_modeline_applied.md', 'um exemplo vim: nuw=7')
vim.wo.numberwidth = 4
local ok_open = pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(applied))

check("opening a note does not error", ok_open, "pcall failed")
check("and the note's text was not applied as configuration",
  vim.wo.numberwidth ~= 7, 'numberwidth=' .. tostring(vim.wo.numberwidth))
check("and Vim does not name a modeline as the source",
  nuw_source():find('modeline', 1, true) == nil, nuw_source())

-- The reported case: an unknown option name, which is what raised E518.
local broken = make_note('0002_note_modeline_error.md', 'um exemplo ex: Será')

local function messages_have_e518()
  return vim.fn.execute('messages'):find('E518', 1, true) ~= nil
end

local ok_open2 = pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(broken))
check("opening the reported note does not error", ok_open2 and not messages_have_e518(),
  'pcall=' .. tostring(ok_open2) .. ' e518=' .. tostring(messages_have_e518()))

-- Save, with the modeline-looking line still in the last five lines. This is
-- the trigger PKM owned: the Syntax refire in BufWritePost.
vim.api.nvim_buf_set_lines(0, 18, 19, false, { 'corpo alterado' })
local ok_write = pcall(vim.cmd, 'write')
vim.wait(1500, function() return false end)

check("saving it does not error", ok_write and not messages_have_e518(),
  'pcall=' .. tostring(ok_write) .. ' e518=' .. tostring(messages_have_e518()))

-- A second save: the post-write path runs again, and so does the refire.
vim.api.nvim_buf_set_lines(0, 18, 19, false, { 'corpo alterado de novo' })
local ok_write2 = pcall(vim.cmd, 'write')
vim.wait(1500, function() return false end)

check("and neither does saving it again", ok_write2 and not messages_have_e518(),
  'pcall=' .. tostring(ok_write2) .. ' e518=' .. tostring(messages_have_e518()))

-- =============================================================================
-- The guard is on the buffer, where the note is
-- =============================================================================

check("the note's buffer has modelines off",
  vim.bo.modeline == false, tostring(vim.bo.modeline))
check("while the global option is untouched",
  vim.go.modeline == true, tostring(vim.go.modeline))

-- =============================================================================

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
