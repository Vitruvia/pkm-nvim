-- =============================================================================
-- pkm.commands.list — ordered/unordered list editing
-- =============================================================================
-- Dependencies : pkm.markdown (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local M = {}

function M.register()

  -- :PKMConvertList [to_ordered|to_unordered] — ordered ↔ unordered conversion.
  vim.api.nvim_create_user_command('PKMConvertList', function(opts)
    local md  = require('pkm.markdown')
    local dir = opts.args ~= '' and opts.args or nil
    if dir and dir ~= 'to_ordered' and dir ~= 'to_unordered' then
      vim.notify('[pkm] invalid direction: use to_ordered or to_unordered',
        vim.log.levels.WARN)
      return
    end
    if opts.range > 0 then
      md.convert_list(opts.line1, opts.line2, dir)
    else
      md.convert_list_at_cursor(dir)
    end
  end, {
    range    = true,
    nargs    = '?',
    complete = function() return { 'to_ordered', 'to_unordered' } end,
    desc     = 'Convert list between ordered/unordered; optional direction arg',
  })

  vim.api.nvim_create_user_command('PKMRenumberList', function(opts)
    local md = require('pkm.markdown')
    if opts.range > 0 then
      md.renumber_sequence(opts.line1, opts.line2)
    else
      md.renumber_at_cursor()
    end
  end, { range = true, desc = 'Renumber ordered sequence in range or current paragraph' })

end

return M
