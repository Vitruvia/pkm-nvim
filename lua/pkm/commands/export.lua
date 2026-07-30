-- =============================================================================
-- pkm.commands.export — exporting notes out of the vault
-- =============================================================================
-- Dependencies : pkm.args, pkm.export (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- `:PKMExport <verb>` — bare opens the mode menu (simple or deep), and the
-- verbs `simple` / `deep` skip straight to one. :PKMExport is the context
-- itself, as it already was the export command, so no new top-level name.
-- Exporting a named view lives with the view surface (:PKMView export).
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local M = {}

function M.register()

  -- :PKMExport — simple (filter only) or deep (filter, then walk the citation
  -- graph out from the matches). Bare, the native vim.ui.select menu: the choice
  -- set is small and fixed, so it does not warrant a panel of its own.
  local EXPORT_VERBS = { 'simple', 'deep' }

  vim.api.nvim_create_user_command('PKMExport', function(opts)
    local export = require('pkm.export')
    local p = require('pkm.args').parse(opts, { verbs = EXPORT_VERBS })
    if p.verb == 'simple' then
      export.interactive_export()
    elseif p.verb == 'deep' then
      export.deep_export()
    else
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
    end
  end, {
    nargs    = '?',
    complete = function(arg_lead)
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, EXPORT_VERBS)
    end,
    desc = 'Export notes: :PKMExport [simple|deep] (bare opens the mode menu)',
  })

end

return M
