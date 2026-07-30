-- =============================================================================
-- pkm.commands.trash — restoring and emptying the PKM trash
-- =============================================================================
-- Dependencies : pkm.args, pkm.trash (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Trash operations. `:PKMTrash <verb>` — restore (the default: open the restore
-- panel), empty. Emptying always confirms.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

--- Open the browse/search/restore panel.
local function act_restore()
  require('pkm.trash').open_restore_panel()
end

--- Permanently delete all trashed notes and strip backlinks, after confirming.
local function act_empty()
  local trash = require('pkm.trash')
  local entries = trash.list()
  if #entries == 0 then
    vim.notify('[pkm] trash is already empty', vim.log.levels.INFO)
    return
  end
  vim.fn.inputsave()
  local confirm = vim.fn.input(string.format(
    'Permanently delete %d trashed note%s and strip backlinks? (yes/no): ',
    #entries, #entries == 1 and '' or 's'))
  vim.fn.inputrestore()
  if confirm:lower() ~= 'yes' then
    vim.notify('[pkm] cancelled', vim.log.levels.INFO)
    return
  end
  local count = trash.empty()
  vim.notify(string.format('[pkm] permanently deleted %d note%s from trash',
    count, count == 1 and '' or 's'), vim.log.levels.INFO)
end

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- :PKMTrash — the context form: restore (default) | empty
  -- ---------------------------------------------------------------------------
  local TRASH_VERBS = { 'restore', 'empty' }

  vim.api.nvim_create_user_command('PKMTrash', function(opts)
    local p = require('pkm.args').parse(opts, { verbs = TRASH_VERBS, default = 'restore' })
    if p.verb == 'empty' then
      act_empty()
    else
      act_restore()
    end
  end, {
    nargs    = '?',
    complete = function(arg_lead)
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, TRASH_VERBS)
    end,
    desc = 'Trash: :PKMTrash [restore] | empty',
  })

end

return M
