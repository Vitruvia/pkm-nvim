-- =============================================================================
-- pkm.commands.list — ordered/unordered list editing
-- =============================================================================
-- Dependencies : pkm.args, pkm.markdown (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- List operations reached two ways. `:PKMList <verb>` is the context form the
-- command clearup introduces — convert, renumber — both range-aware. The
-- original names (`:PKMConvertList`, `:PKMRenumberList`) stay as aliases and
-- drive the same cores.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

--- Convert a list between ordered and unordered, over a range or at the cursor.
---@param dir 'to_ordered'|'to_unordered'|nil
---@param opts table  command opts (reads range/line1/line2)
local function do_convert(dir, opts)
  if dir and dir ~= 'to_ordered' and dir ~= 'to_unordered' then
    vim.notify('[pkm] invalid direction: use to_ordered or to_unordered',
      vim.log.levels.WARN)
    return
  end
  local md = require('pkm.markdown')
  if opts.range > 0 then
    md.convert_list(opts.line1, opts.line2, dir)
  else
    md.convert_list_at_cursor(dir)
  end
end

--- Renumber an ordered sequence, over a range or in the current paragraph.
---@param opts table  command opts (reads range/line1/line2)
local function do_renumber(opts)
  local md = require('pkm.markdown')
  if opts.range > 0 then
    md.renumber_sequence(opts.line1, opts.line2)
  else
    md.renumber_at_cursor()
  end
end

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- :PKMList — the context form
  -- ---------------------------------------------------------------------------
  local LIST_VERBS = { 'convert', 'renumber' }

  vim.api.nvim_create_user_command('PKMList', function(opts)
    local p = require('pkm.args').parse(opts, { verbs = LIST_VERBS })
    if p.verb == 'convert' then
      do_convert(p.positional[1], opts)
    elseif p.verb == 'renumber' then
      do_renumber(opts)
    else
      vim.notify('[pkm] :PKMList convert [to_ordered|to_unordered] | renumber',
        vim.log.levels.WARN)
    end
  end, {
    range    = true,
    nargs    = '*',
    complete = function(arg_lead, line)
      local out
      if line:match('^%s*%d*[,%d]*PKMList%s+[Cc][Oo][Nn][Vv][Ee][Rr][Tt]%s') then
        out = { 'to_ordered', 'to_unordered' }
      else
        out = LIST_VERBS
      end
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, out)
    end,
    desc = 'Lists: :PKMList convert [to_ordered|to_unordered] | renumber',
  })

end

return M
