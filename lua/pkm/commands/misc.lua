-- =============================================================================
-- pkm.commands.misc — the standalone commands that head no context
-- =============================================================================
-- Dependencies : pkm (init), pkm.check, pkm.ui, pkm.utils (lazy)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Sync control, the read-only vault audit, and statistics. Each is a single
-- command with no siblings, so it belongs to no larger context.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- Sync control
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMToggleAutoSync', function()
    local pkm = require('pkm')
    pkm.config.sync.auto_sync_on_save = not pkm.config.sync.auto_sync_on_save
    local status = pkm.config.sync.auto_sync_on_save and 'enabled' or 'disabled'
    vim.notify('Auto-sync on save: ' .. status, vim.log.levels.INFO)
    vim.api.nvim_clear_autocmds({ group = 'PKMSync' })
    if pkm.config.sync.enabled then pkm.setup_sync_autocmds() end
  end, { desc = 'Toggle automatic reference synchronization' })

  -- ---------------------------------------------------------------------------
  -- Vault audit
  -- ---------------------------------------------------------------------------
  -- Read-only audit of the active vault. The module finds; the command shows —
  -- a clean vault says so and opens nothing, a vault with problems lists them in
  -- a scratch buffer, errors first, each line a path and a one-line reason.
  vim.api.nvim_create_user_command('PKMCheck', function()
    local findings = require('pkm.check').run()
    if #findings == 0 then
      vim.notify('[pkm] check: no problems found', vim.log.levels.INFO)
      return
    end

    local errors = 0
    for _, f in ipairs(findings) do
      if f.severity == 'error' then errors = errors + 1 end
    end

    local root = require('pkm').config.root_path or ''
    local lines = {
      string.format('PKM check — %d finding%s (%d error%s)',
        #findings, #findings == 1 and '' or 's', errors, errors == 1 and '' or 's'),
      string.rep('─', 60),
    }
    for _, f in ipairs(findings) do
      local where = f.path and f.path:gsub(vim.pesc(root .. '/'), ''):gsub(vim.pesc(root), '') or ''
      lines[#lines + 1] = string.format('%-7s %s', f.severity:upper(), f.message)
      if where ~= '' then lines[#lines + 1] = '        ' .. where end
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden  = 'wipe'
    vim.bo[buf].filetype   = 'pkm-check'
    require('pkm.utils').focus_editing_win()
    vim.api.nvim_set_current_buf(buf)

    vim.notify(string.format('[pkm] check: %d finding%s (%d error%s)',
      #findings, #findings == 1 and '' or 's', errors, errors == 1 and '' or 's'),
      errors > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
  end, { desc = 'Audit the vault: frontmatter, the citation graph, numbering, vault references' })

  -- ---------------------------------------------------------------------------
  -- Stats
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMStats', function()
    require('pkm.ui').show_stats()
  end, { desc = 'Show PKM statistics' })

end

return M
