-- =============================================================================
-- pkm.commands.panel — the persistent panels and PKM mode toggles
-- =============================================================================
-- Dependencies : pkm.ui, pkm.views, pkm.mode (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- The buffer panel, PKM mode, and the explorer (sidebar + buffer panel as a
-- unit).
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- Buffer panel
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMBuffers', function()
    require('pkm.ui').toggle_bufpanel()
  end, { desc = 'Toggle the persistent bottom buffer-list panel' })

  -- ---------------------------------------------------------------------------
  -- Toggles
  -- ---------------------------------------------------------------------------
  -- :PKMMode [on|off] — activate, deactivate, or toggle PKM session context.
  vim.api.nvim_create_user_command('PKMMode', function(opts)
    require('pkm.mode').set(opts.args:match('^%s*(.-)%s*$'))
  end, {
    nargs = '?',
    complete = function() return { 'on', 'off' } end,
    desc = 'Toggle PKM mode (explorer + index + syntax)',
  })

  -- :PKMExplorer — toggle sidebar + bufpanel as a unit, independent of mode state.
  -- If both open: close both. If either closed: open both.
  vim.api.nvim_create_user_command('PKMExplorer', function()
    local views = require('pkm.views')
    local ui    = require('pkm.ui')
    local s = views.is_sidebar_open()
    local b = ui.is_bufpanel_open()
    if s and b then
      views.open_sidebar()
      ui.toggle_bufpanel()
    else
      if not s then views.open_sidebar()   end
      if not b then ui.toggle_bufpanel()   end
    end
  end, { desc = 'Toggle PKM explorer (sidebar + buffer panel)' })

end

return M
