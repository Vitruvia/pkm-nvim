-- =============================================================================
-- pkm.commands — User command registration
-- =============================================================================
-- Dependencies : the per-context command modules in this directory
-- Consumed by  : pkm.init (called once during setup)
--
-- The :PKM* surface used to live in one file; it is now split into one module
-- per command context (note, tag, cite, browse, view, vault, trash, list,
-- header, panel, export, misc), each exposing its own `register()`. This file
-- wires them together and preserves the single entry point `register()` that
-- pkm.init calls, so `require('pkm.commands')` behaves exactly as before.
--
-- Every handler still uses lazy require, so no feature module is loaded until
-- its command is first invoked. Handlers that call init.lua functions use
-- require('pkm') rather than a local M reference.
--
-- Public API:
--   register() → Register all :PKM* commands with Neovim
-- =============================================================================

local M = {}

-- The context modules, in the order they are registered. Order is immaterial to
-- correctness (each command is independent), but a stable list keeps the diff
-- of adding or moving a context small and readable.
local CONTEXTS = {
  'note', 'tag', 'cite', 'browse', 'view', 'vault',
  'trash', 'list', 'header', 'panel', 'export', 'misc',
}

--- Register all :PKM* user commands. Called once by init.lua during setup.
--- Safe to call again (nvim_create_user_command overwrites existing commands).
function M.register()
  for _, name in ipairs(CONTEXTS) do
    require('pkm.commands.' .. name).register()
  end
end

return M
