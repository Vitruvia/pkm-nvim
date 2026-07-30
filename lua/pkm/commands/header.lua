-- =============================================================================
-- pkm.commands.header — markdown header editing and navigation
-- =============================================================================
-- Dependencies : pkm.markdown (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local M = {}

function M.register()

  -- Renamed from :PKMNextHeader in v1.10.0. It edits the buffer, while
  -- :PKMHeaderNext only moves the cursor; under the old pair of names the
  -- wrong one was a completion away, and the wrong one writes. The keymap
  -- config key stays `next_header` so existing setups keep working.
  vim.api.nvim_create_user_command('PKMHeaderAppend', function()
    require('pkm.markdown').append_next_header()
  end, { desc = 'Duplicate current header with counter incremented, append at EOF' })

  -- :PKMHeaderNext / :PKMHeaderPrev [same|h1-h6], with an optional count —
  -- :3PKMHeaderNext. Complements Neovim's native ]] / [[ (see markdown.lua
  -- § Header navigation for what those already cover).
  --
  -- The level is `h2`, not `2`, because these commands take a count, and Vim
  -- reads a leading number in the arguments AS the count: `:PKMHeaderNext 6`
  -- means six headers ahead, and always did. Spelling the level `h6` leaves
  -- one reading per form instead of two for the same words.
  local function header_motion(dir)
    return function(opts)
      local level = nil
      if opts.args ~= '' then
        level = (opts.args == 'same') and 'same' or tonumber(opts.args:match('^[hH]([1-6])$'))
        if level == nil then
          vim.notify(
            '[pkm] use same or h1-h6 for the level; a bare number is the count',
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

  local header_levels = { 'same', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6' }

  vim.api.nvim_create_user_command('PKMHeaderNext', header_motion('next'), {
    count    = true,
    nargs    = '?',
    complete = function() return header_levels end,
    desc     = 'Jump to the next header (any level; arg restricts it)',
  })

  vim.api.nvim_create_user_command('PKMHeaderPrev', header_motion('prev'), {
    count    = true,
    nargs    = '?',
    complete = function() return header_levels end,
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
