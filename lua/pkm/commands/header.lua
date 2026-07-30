-- =============================================================================
-- pkm.commands.header — markdown header editing and navigation
-- =============================================================================
-- Dependencies : pkm.args, pkm.markdown (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Header operations reached two ways. `:PKMHeader <verb>` is the context form
-- the command clearup introduces — append, next, prev, levelup, leveldown. The
-- original names (`:PKMHeaderAppend`, `:PKMHeaderNext`, …) stay as aliases and
-- drive the same cores.
--
-- One thing does not fold cleanly: `:PKMHeaderNext`/`Prev` take a Vim count
-- (`:3PKMHeaderNext`), while the level-shifts take a range — a single command
-- cannot carry both. So the context form reads the motion count as an argument
-- (`:PKMHeader next 3`, `:PKMHeader next h2`) and keeps `range` for the shifts;
-- the `:count` prefix stays on the `:PKMHeaderNext`/`Prev` aliases.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local HEADER_LEVELS = { 'same', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6' }

--- Read a header motion's count and level from its positional arguments and jump.
--- The level is `h2`, not `2`, because a bare number is the count.
---@param dir 'next'|'prev'
---@param positional string[]
local function do_motion(dir, positional)
  local level, count = nil, 1
  for _, tok in ipairs(positional) do
    if tok == 'same' then
      level = 'same'
    elseif tok:match('^[hH][1-6]$') then
      level = tonumber(tok:match('[1-6]'))
    elseif tok:match('^%d+$') then
      count = tonumber(tok)
    else
      vim.notify('[pkm] use same or h1-h6 for the level; a bare number is the count',
        vim.log.levels.WARN)
      return
    end
  end
  require('pkm.markdown').goto_heading({ dir = dir, count = count, level = level })
end

--- Shift header levels across a range, defaulting to the whole buffer.
---@param dir 'up'|'down'
---@param opts table  command opts (reads range/line1/line2)
local function do_shift(dir, opts)
  local l1 = opts.range > 0 and opts.line1 or 1
  local l2 = opts.range > 0 and opts.line2 or vim.fn.line('$')
  require('pkm.markdown').shift_header_level(dir, l1, l2)
end

--- The Vim-count motion handler for the :PKMHeaderNext/Prev aliases, where the
--- count comes as `:3PKMHeaderNext` and the level as the sole argument.
local function alias_motion(dir)
  return function(opts)
    local level = nil
    if opts.args ~= '' then
      level = (opts.args == 'same') and 'same' or tonumber(opts.args:match('^[hH]([1-6])$'))
      if level == nil then
        vim.notify('[pkm] use same or h1-h6 for the level; a bare number is the count',
          vim.log.levels.WARN)
        return
      end
    end
    require('pkm.markdown').goto_heading({
      dir   = dir,
      count = opts.count > 0 and opts.count or 1,
      level = level,
    })
  end
end

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- :PKMHeader — the context form
  -- ---------------------------------------------------------------------------
  local HEADER_VERBS = { 'append', 'next', 'prev', 'levelup', 'leveldown' }

  vim.api.nvim_create_user_command('PKMHeader', function(opts)
    local p = require('pkm.args').parse(opts, { verbs = HEADER_VERBS })
    if p.verb == 'append' then
      require('pkm.markdown').append_next_header()
    elseif p.verb == 'next' then
      do_motion('next', p.positional)
    elseif p.verb == 'prev' then
      do_motion('prev', p.positional)
    elseif p.verb == 'levelup' then
      do_shift('up', opts)
    elseif p.verb == 'leveldown' then
      do_shift('down', opts)
    else
      vim.notify('[pkm] :PKMHeader append | next|prev [same|h1-h6] [count] | levelup|leveldown',
        vim.log.levels.WARN)
    end
  end, {
    range    = true,
    nargs    = '*',
    complete = function(arg_lead, line)
      local out
      if line:match('^%s*%d*PKMHeader%s+[Nn][Ee][Xx][Tt]%s')
      or line:match('^%s*%d*PKMHeader%s+[Pp][Rr][Ee][Vv]%s') then
        out = HEADER_LEVELS
      else
        out = HEADER_VERBS
      end
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, out)
    end,
    desc = 'Headers: :PKMHeader append | next|prev [same|h1-h6] [count] | levelup|leveldown',
  })

  -- ---------------------------------------------------------------------------
  -- Aliases
  -- ---------------------------------------------------------------------------
  -- Renamed from :PKMNextHeader in v1.10.0. It edits the buffer, while
  -- :PKMHeaderNext only moves the cursor; under the old pair of names the
  -- wrong one was a completion away, and the wrong one writes. The keymap
  -- config key stays `next_header` so existing setups keep working.
  vim.api.nvim_create_user_command('PKMHeaderAppend', function()
    require('pkm.markdown').append_next_header()
  end, { desc = 'Duplicate current header with counter incremented, append at EOF' })

  vim.api.nvim_create_user_command('PKMHeaderNext', alias_motion('next'), {
    count    = true,
    nargs    = '?',
    complete = function() return HEADER_LEVELS end,
    desc     = 'Jump to the next header (any level; arg restricts it)',
  })

  vim.api.nvim_create_user_command('PKMHeaderPrev', alias_motion('prev'), {
    count    = true,
    nargs    = '?',
    complete = function() return HEADER_LEVELS end,
    desc     = 'Jump to the previous header (any level; arg restricts it)',
  })

  vim.api.nvim_create_user_command('PKMHeaderLevelUp', function(opts)
    require('pkm.markdown').shift_header_level('up', opts.line1, opts.line2)
  end, { range = '%', desc = 'Increase header level in range (default: whole buffer)' })

  vim.api.nvim_create_user_command('PKMHeaderLevelDown', function(opts)
    require('pkm.markdown').shift_header_level('down', opts.line1, opts.line2)
  end, { range = '%', desc = 'Decrease header level in range (default: whole buffer)' })

end

return M
