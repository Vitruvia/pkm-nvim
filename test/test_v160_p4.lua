-- test/test_v160_p4.lua
-- Tests for v1.6.0 Phase 4: relative-split picker actions.
--
-- Scope note: the flash bug ("PKMViews -> PKMBrowse console flash") was
-- confirmed resolved by manual reproduction attempt (both the new <C-f>
-- in-panel toggle and the old direct-command sequence were tried; neither
-- flashes) -- nothing to unit-test there. What's tested here is the pure
-- decision logic behind the actual new feature: which window a <C-v>/<C-x>
-- split action should target, given the state of the invocation window
-- captured when the picker was opened. The window-opening side effects
-- themselves (vim.cmd('vsplit ...'), nvim_set_current_win) are a thin,
-- untested wrapper around this, per the project's pure-logic-first rule.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v160_p4.lua" -c "qa!"

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

print("== pure: resolve_split_target ==")

do
  check("right, invocation still valid -> 'invocation'",
    views._resolve_split_target('right', false, true) == 'invocation')
  check("right, invocation vanished -> 'rightmost' fallback",
    views._resolve_split_target('right', false, false) == 'rightmost')
  check("right, invocation vanished, was sidebar -> still 'rightmost'"
      .. " (sidebar-ness is irrelevant to the right direction)",
    views._resolve_split_target('right', true, false) == 'rightmost')
  check("right, invocation was sidebar but still valid -> 'invocation'"
      .. " (splitting right of the sidebar is fine, only left is excluded)",
    views._resolve_split_target('right', true, true) == 'invocation')
end

do
  check("left, invocation valid and not sidebar -> 'invocation'",
    views._resolve_split_target('left', false, true) == 'invocation')
  check("left, invocation was sidebar -> nil (disabled; nothing left of it)",
    views._resolve_split_target('left', true, true) == nil)
  check("left, invocation vanished -> nil (no fallback for left)",
    views._resolve_split_target('left', false, false) == nil)
  check("left, invocation vanished AND was sidebar -> nil (still disabled)",
    views._resolve_split_target('left', true, false) == nil)
end

print(string.format("\n%s", failures == 0 and "ALL PASS" or (failures .. " FAILURE(S)")))
if failures > 0 then vim.cmd("cquit 1") end
