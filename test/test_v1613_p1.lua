-- test/test_v1613_p1.lua
-- pkm.sidebar extraction — the persistent sidebar CONTAINER moved out of
-- views.lua onto its own module (mirroring nav/buffers on pkm.panel). This is a
-- behavior-preserving refactor gated by the existing sidebar battery (v1490 /
-- v1510 / v1520 / v1530 / v1540 / v160); this test locks the extraction BOUNDARY
-- itself: the container API lives on pkm.sidebar, pkm.views re-exports it (so the
-- historical views.<fn> call sites keep working), and the `views` provider is
-- registered with the container and drivable through views.open_sidebar.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1613_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root, projects = { ['Foos'] = 'tag:foo', ['Bars'] = 'tag:bar' } })

local sidebar = require('pkm.sidebar')
local views   = require('pkm.views')

print("== the container API lives on pkm.sidebar ==")
for _, fn in ipairs({
  'get_state', 'is_sidebar_open', 'get_sidebar_win', 'open', 'close', 'refresh',
  'refresh_sidebar_if_open', 'register_sidebar_provider', 'sidebar_provider',
  'sidebar_provider_is', 'set_sidebar_provider', 'cycle_sidebar_provider',
  'show_sidebar_provider', 'win_is_markdown', 'autoswitch_tick', 'set_autoswitch',
  'autoswitch_enabled', 'setup',
}) do
  check("pkm.sidebar." .. fn .. " is a function", type(sidebar[fn]) == 'function')
end

print("\n== pkm.views re-exports the container API (same function identities) ==")
for _, fn in ipairs({
  'is_sidebar_open', 'get_sidebar_win', 'refresh_sidebar_if_open',
  'register_sidebar_provider', 'sidebar_provider', 'sidebar_provider_is',
  'set_sidebar_provider', 'cycle_sidebar_provider', 'show_sidebar_provider',
  'autoswitch_tick', 'set_autoswitch', 'autoswitch_enabled',
}) do
  check("views." .. fn .. " === sidebar." .. fn, views[fn] == sidebar[fn])
end
check("views.open_sidebar and views.focus_sidebar stay views-owned (not re-exports)",
  type(views.open_sidebar) == 'function' and type(views.focus_sidebar) == 'function'
  and views.open_sidebar ~= sidebar.open)

print("\n== the `views` provider is registered with the container ==")
check("sidebar is closed at the start", sidebar.is_sidebar_open() == false)
check("no active provider while closed", sidebar.sidebar_provider() == nil)

print("\n== views.open_sidebar drives the container onto the views provider ==")
views.open_sidebar()   -- context-driven no-name open (no markdown focused → views overview)
check("the container reports open after views.open_sidebar()", sidebar.is_sidebar_open() == true)
check("the active provider is 'views'", sidebar.sidebar_provider() == 'views',
  tostring(sidebar.sidebar_provider()))
check("sidebar_provider_is('views') agrees", sidebar.sidebar_provider_is('views') == true)
local st = sidebar.get_state()
check("the container exposes per-tab state while open", type(st) == 'table' and st.win ~= nil,
  vim.inspect(st))
check("a view is rendered in the sidebar", (function()
  local lines = vim.api.nvim_buf_get_lines(st.buf, 0, -1, false)
  for _, l in ipairs(lines) do if l:find('Foos', 1, true) or l:find('Bars', 1, true) then return true end end
  return false
end)(), "no view name found in the sidebar buffer")

print("\n== toggling closed through the same entry point ==")
views.open_sidebar()   -- no-name again toggles it closed
check("the container reports closed after the toggle", sidebar.is_sidebar_open() == false)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
