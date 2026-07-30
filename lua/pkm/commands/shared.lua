-- =============================================================================
-- pkm.commands.shared — helpers used across more than one command context
-- =============================================================================
-- Dependencies : pkm.utils (lazy, inside the helper)
-- Consumed by  : pkm.commands.note, .tag, .browse, .view
--
-- The command surface is split into one file per context (note, tag, cite, …).
-- Anything genuinely shared by several of them lives here, so it is single-
-- sourced rather than copied. Today that is one helper.
--
-- Public API:
--   focus_main_win(where?) → move focus to a real editing window
-- =============================================================================

local M = {}

--- If the current window is a PKM panel (sidebar, bufpanel) or netrw, switch
--- focus to a real editing window, creating one if the tabpage has none.
--- Ensures commands never open note buffers inside a panel.
---
--- The search itself lives in `pkm.utils` — it was duplicated in the command
--- layer and in `views`, and note creation needed a third copy, which is one
--- copy too many.
---@param where nil|'left'|'right'|integer  Passed through to utils
function M.focus_main_win(where)
  require('pkm.utils').focus_editing_win(where)
end

return M
