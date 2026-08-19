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

  -- The header names the panel and points at '?' — it does not carry the
  -- keymap hints themselves. This assertion used to demand 'Views' and
  -- 'browse all' on one line, which the panel never rendered together; it
  -- passed only while the two lived in the same string. The browse hint is
  -- discovered through '?', so it is checked below, where it actually is.
  local header_ok, found_view = false, false
  for _, line in ipairs(lines) do
    if line:find('Views', 1, true) and line:find('? help', 1, true) then header_ok = true end
    if line:find('__test_v160_p3_view', 1, true) then found_view = true end
  end
  check("header names the panel and advertises '? help'", header_ok,
    lines[1] and ('first line: ' .. lines[1]) or 'no lines')
  check("scratch view appears in the panel", found_view)

  -- '?' is the only route to the keymap list, so the <C-f>-to-browse hint is
  -- only discoverable if the overlay carries it. 'normal' without the bang:
  -- the bang skips mappings, and the mapping is the thing under test.
  vim.api.nvim_set_current_win(win)
  vim.cmd('normal ?')
  local help_win, help_has_browse = nil, false
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= win and vim.api.nvim_win_get_config(w).relative ~= '' then
      help_win = w
      for _, l in ipairs(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)) do
        if l:find('<C-f>', 1, true) and l:find('browse all notes', 1, true) then
          help_has_browse = true
        end
      end
    end
  end
  check("'?' opens the keymap help overlay", help_win ~= nil)
  check("and the overlay carries the <C-f>-to-browse hint", help_has_browse)
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    vim.api.nvim_win_close(help_win, true)
  end

  local keymap_lhs, keymap_lower = {}, {}
  for _, km in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    keymap_lhs[km.lhs] = true
    -- nvim_buf_get_keymap already returns bracketed keys like '<C-f>' as
    -- '<c-f>' (lowercased inside the brackets, regardless of how it was
    -- registered) — a plain string compare against '<C-f>' silently
    -- never matches. Plain single-character keys (d/D/n/u below) have no
    -- such case-folding and are checked against the exact, unmodified lhs.
    keymap_lower[km.lhs:lower()] = true
  end
  check("no 'd' keymap in views panel (deletion lives in the separate panel only)",
    keymap_lhs['d'] == nil)
  check("no 'D' keymap in views panel", keymap_lhs['D'] == nil)
  check("'<C-f>' is bound (mode switch)", keymap_lower['<c-f>'] ~= nil)
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

print("\n== view-deletion selector: picker + confirm performs the delete ==")
do
  -- v1.81.0: deletion is the shared Telescope picker (headless → pkm.ui.pick_list
  -- → vim.ui.select), then a native vim.fn.confirm. Both are stubbed to drive the
  -- selection and the "Yes" so the full path — pick the view, confirm, delete —
  -- runs without a human. The scratch view was saved at the top of the file.
  check("scratch view present before delete",
    vim.tbl_contains(views.list(), '__test_v160_p3_view'))

  local o_select, o_confirm = vim.ui.select, vim.fn.confirm
  local picker_saw_scratch = false
  vim.ui.select = function(items, _opts, on_choice)
    for _, it in ipairs(items) do
      local val = (type(it) == 'table') and it.value or it
      if val == '__test_v160_p3_view' then picker_saw_scratch = true end
    end
    for _, it in ipairs(items) do
      local val = (type(it) == 'table') and it.value or it
      if val == '__test_v160_p3_view' then on_choice(it); return end
    end
    on_choice(nil)
  end
  vim.fn.confirm = function() return 1 end   -- "Yes"
  local ok = pcall(views.open_view_deletion_panel)
  vim.ui.select, vim.fn.confirm = o_select, o_confirm

  check("deletion selector ran without error", ok)
  check("scratch view was offered in the picker", picker_saw_scratch)
  check("view deleted through the picker + confirm",
    not vim.tbl_contains(views.list(), '__test_v160_p3_view'))
end

print(string.format("\n%s", failures == 0 and "ALL PASS" or (failures .. " FAILURE(S)")))
if failures > 0 then vim.cmd("cquit 1") end
