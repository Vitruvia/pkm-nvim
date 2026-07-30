-- =============================================================================
-- pkm.commands.trash — restoring and emptying the PKM trash
-- =============================================================================
-- Dependencies : pkm.trash (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local M = {}

function M.register()

  -- :PKMRestoreNote — open the browse/search/restore panel.
  vim.api.nvim_create_user_command('PKMRestoreNote', function()
    require('pkm.trash').open_restore_panel()
  end, { desc = 'Browse and restore notes from the PKM trash' })

  -- :PKMEmptyTrash — permanently delete all trashed notes and strip backlinks.
  vim.api.nvim_create_user_command('PKMEmptyTrash', function()
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
  end, { desc = 'Permanently delete all PKM trash and strip backlinks' })

end

return M
