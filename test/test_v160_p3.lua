-- test/test_v160_p3.lua
-- Tests for v1.6.0 Phase 3: views panel + view-deletion panel, and the
-- pure window-slot helpers behind N<CR>/<C-v>.
--
-- Note on scope: N<CR>'s live window-targeting itself needed no code
-- change (it was already correct) except being refactored onto these two
-- shared pure helpers — so what's tested here is (a) those helpers in
-- isolation, and (b) the new panels' lifecycle/content/no-delete-key
-- invariants, matching the pattern established in test_v160_p1.lua and
-- test_v160_p2.lua. The interactive confirm-dialog step in the deletion
-- panel, and the actual <Tab>/<C-v>/N<CR> keypresses, are left to manual
-- smoke — same call made for the equivalent interactive steps in both
-- prior phase test files.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v160_p3.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

local views = require('pkm.views')

print("== pure: sort_wins_by_col ==")
do
  local input = {
    { win = 'C', col = 40 },
    { win = 'A', col = 0 },
    { win = 'B', col = 20 },
  }
  local sorted = views._sort_wins_by_col(input)
  check("sorts ascending by col",
    sorted[1].win == 'A' and sorted[2].win == 'B' and sorted[3].win == 'C')
  check("does not mutate the input array's order", input[1].win == 'C',
    "input[1] should still be 'C' — the original, pre-sort order")
  check("returns a new array (different table identity)", sorted ~= input)
end

do
  local sorted = views._sort_wins_by_col({})
  check("empty input -> empty output", #sorted == 0)
end

print("\n== pure: resolve_window_slot ==")
do
  check("n=2, count=5 -> 2", views._resolve_window_slot(2, 5) == 2)
  check("n=1, count=1 -> 1", views._resolve_window_slot(1, 1) == 1)
  check("n=9, count=1 -> nil (the '9<CR> with one window' case)",
    views._resolve_window_slot(9, 1) == nil)
  check("n=0 -> nil (no count given)", views._resolve_window_slot(0, 5) == nil)
  check("n=-1 -> nil", views._resolve_window_slot(-1, 5) == nil)
  check("count=0 (no editing windows), n=1 -> nil",
    views._resolve_window_slot(1, 0) == nil)
  check("n exactly equals count -> n", views._resolve_window_slot(3, 3) == 3)
end

print("\n== views panel: lifecycle and content (views mode) ==")
do
  local ok_save = views.save('__test_v160_p3_view', 'tag:__nonexistent_tag_marker__')
  check("scratch view saved", ok_save)

  views._views_panel.open({ filter = '', mode = 'views' })
  check("views panel opens", views._views_panel.is_open())

  local win = views._views_panel.get_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local header_ok, found_view = false, false
  for _, line in ipairs(lines) do
    if line:find('Views', 1, true) and line:find('browse all', 1, true) then header_ok = true end
    if line:find('__test_v160_p3_view', 1, true) then found_view = true end
  end
  check("header mentions the C-f-to-browse hint", header_ok)
  check("scratch view appears in the panel", found_view)

  local keymap_lhs, keymap_readable = {}, {}
  for _, km in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    keymap_lhs[km.lhs] = true
    -- Control-key combos come back as their raw byte (Ctrl-F is 0x06), not
    -- the '<C-f>' string — keytrans() converts back to the canonical
    -- <...> notation so the comparison actually means what it says.
    -- Plain printable keys (below) have no such ambiguity and are checked
    -- against the raw lhs directly.
    keymap_readable[vim.fn.keytrans(km.lhs):lower()] = true
  end
  check("no 'd' keymap in views panel (deletion lives in the separate panel only)",
    keymap_lhs['d'] == nil)
  check("no 'D' keymap in views panel", keymap_lhs['D'] == nil)
  check("'<C-f>' is bound (mode switch)", keymap_readable['<c-f>'] ~= nil)
  check("'n' is bound (new view)", keymap_lhs['n'] ~= nil)
  check("'u' is bound (update view)", keymap_lhs['u'] ~= nil)

  views._views_panel.close()
  check("views panel closes", not views._views_panel.is_open())
end

print("\n== views panel: browse mode renders in the same panel ==")
do
  views._views_panel.open({ filter = '', mode = 'browse' })
  check("views panel opens directly into browse mode", views._views_panel.is_open())

  local win = views._views_panel.get_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local browse_header = false
  for _, line in ipairs(lines) do
    if line:find('Browse All', 1, true) then browse_header = true end
  end
  check("header shows Browse All in browse mode", browse_header)

  views._views_panel.close()
end

print("\n== view-deletion panel: lifecycle, content, and a real delete ==")
do
  views._delete_panel.open({ filter = '' })
  check("deletion panel opens", views._delete_panel.is_open())

  local win = views._delete_panel.get_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local lines_before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local found_before = false
  for _, line in ipairs(lines_before) do
    if line:find('__test_v160_p3_view', 1, true) then found_before = true end
  end
  check("scratch view appears in the deletion panel", found_before)

  -- The confirm dialog itself is interactive (vim.fn.confirm) and left to
  -- manual smoke; the delete it ultimately performs is exercised directly.
  local ok_delete = views.delete('__test_v160_p3_view')
  check("M.delete() succeeds", ok_delete)
  check("view no longer in M.list()", not vim.tbl_contains(views.list(), '__test_v160_p3_view'))

  views._delete_panel.refresh()
  local lines_after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local found_after = false
  for _, line in ipairs(lines_after) do
    if line:find('__test_v160_p3_view', 1, true) then found_after = true end
  end
  check("scratch view no longer in the refreshed deletion panel", not found_after)

  views._delete_panel.close()
  check("deletion panel closes", not views._delete_panel.is_open())
end

print(string.format("\n%s", failures == 0 and "ALL PASS" or (failures .. " FAILURE(S)")))
if failures > 0 then vim.cmd("cquit 1") end
