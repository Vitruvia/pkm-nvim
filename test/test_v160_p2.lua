-- test/test_v160_p2.lua
-- Integration-style tests for v1.6.0 Phase 2: the trash-restore panel.
-- Run against a real headless Neovim instance, per the Standing
-- Verification Protocol — trash.lua does real file I/O and manifest
-- read/write, not pure logic.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v160_p2.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== trash restore panel ==")

do
  local trash = require('pkm.trash')

  -- Scratch note in the configured scratch root (set up by min_init.lua's
  -- own pkm.setup() call against a disposable temp directory).
  local pkm = require('pkm')
  local scratch_dir = pkm.config.root_path
  vim.fn.mkdir(scratch_dir, 'p')
  local note_path = scratch_dir .. '/test_v160_p2_note.md'
  vim.fn.writefile({
    '---',
    'title: "Test Note for Trash Panel"',
    '---',
    '',
    'body text',
  }, note_path)

  local before_count = #trash.list()

  check("trash_note() succeeds", trash.trash_note(note_path))
  check("original file gone after trashing", vim.fn.filereadable(note_path) == 0)
  check("manifest grew by one entry", #trash.list() == before_count + 1)

  -- Locate the manifest entry we just created.
  local entry = nil
  for _, e in ipairs(trash.list()) do
    if e.original_path == note_path then entry = e end
  end
  check("manifest entry for our note exists", entry ~= nil)

  if entry then
    -- Open the panel and confirm build_lines reflects the trashed note.
    trash._restore_panel.open({ filter = '' })
    check("restore panel opens", trash._restore_panel.is_open())

    local win = trash._restore_panel.get_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local found = false
    for _, line in ipairs(lines) do
      if line:find('Test Note for Trash Panel', 1, true) then found = true end
    end
    check("panel lists the trashed note", found)

    -- No destructive key: check the REAL registered buffer-local normal-mode
    -- keymaps, not just the source spec — this is what would actually fire
    -- if someone pressed d/D in the panel.
    local keymap_lhs = {}
    for _, km in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      keymap_lhs[km.lhs] = true
    end
    check("no 'd' keymap bound in restore panel", keymap_lhs['d'] == nil)
    check("no 'D' keymap bound in restore panel", keymap_lhs['D'] == nil)
    check("'<CR>' is bound (restore action)", keymap_lhs['<CR>'] ~= nil)
    check("'q' is bound (close, panel.lua default)", keymap_lhs['q'] ~= nil)

    trash._restore_panel.close()
    check("restore panel closes", not trash._restore_panel.is_open())

    -- Round-trip: restore and confirm the file returns and the manifest
    -- shrinks back down.
    check("restore_note() succeeds", trash.restore_note(entry))
    check("file exists again at original path", vim.fn.filereadable(note_path) == 1)
    check("manifest shrank back to original count", #trash.list() == before_count)
  end

  -- Cleanup regardless of outcome.
  if vim.fn.filereadable(note_path) == 1 then vim.fn.delete(note_path) end
end

print(string.format("\n%s", failures == 0 and "ALL PASS" or (failures .. " FAILURE(S)")))
if failures > 0 then vim.cmd("cquit 1") end
