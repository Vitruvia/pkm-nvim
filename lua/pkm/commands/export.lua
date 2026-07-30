-- =============================================================================
-- pkm.commands.export — exporting notes out of the vault
-- =============================================================================
-- Dependencies : pkm.export (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- The general export command. Exporting a named view lives with the view
-- surface (:PKMExportView in pkm.commands.view).
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local M = {}

function M.register()

  -- :PKMExport — simple (filter only) or deep (filter, then walk the citation
  -- graph out from the matches). Native vim.ui.select: the choice set is small
  -- and fixed, so it does not warrant a panel of its own.
  vim.api.nvim_create_user_command('PKMExport', function()
    local export = require('pkm.export')
    vim.ui.select(
      { 'Simple — export the notes you select',
        'Deep   — also export what those notes cite and what cites them' },
      { prompt = 'Export mode:' },
      function(_, idx)
        if idx == 1 then
          export.interactive_export()
        elseif idx == 2 then
          export.deep_export()
        end
      end)
  end, { desc = 'Export notes: filter form, optionally expanded across citations' })

end

return M
