-- =============================================================================
-- pkm.commands.panel — the persistent panels and PKM mode toggles
-- =============================================================================
-- Dependencies : pkm.args, pkm.ui, pkm.views, pkm.mode (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- The panels and mode toggles, reached two ways. `:PKMPanel <verb>` is the
-- context form the command clearup introduces — `explorer` (the default:
-- sidebar + buffer panel as a unit), `buffers`, `sidebar`, `mode`. The original
-- names (`:PKMBuffers`, `:PKMExplorer`, `:PKMMode`) stay as aliases and drive
-- the same cores. `sidebar` opens the view sidebar, whose own alias
-- (`:PKMViewSidebar`) lives with the view surface.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

--- Toggle the bottom buffer-list panel.
local function act_buffers()
  require('pkm.ui').toggle_bufpanel()
end

--- Open or toggle the view sidebar (optionally a named view).
local function act_sidebar(name)
  require('pkm.views').open_sidebar(name)
end

--- Activate, deactivate, or toggle PKM session context.
local function act_mode(arg)
  require('pkm.mode').set((arg or ''):match('^%s*(.-)%s*$'))
end

--- Toggle sidebar + buffer panel as a unit, independent of mode state.
--- If both open: close both. If either closed: open both.
local function act_explorer()
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
end

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- :PKMPanel — the context form: explorer (default) | buffers | sidebar | mode
  -- ---------------------------------------------------------------------------
  local PANEL_VERBS = { 'explorer', 'buffers', 'sidebar', 'mode' }

  vim.api.nvim_create_user_command('PKMPanel', function(opts)
    local p = require('pkm.args').parse(opts, { verbs = PANEL_VERBS, default = 'explorer' })
    if p.verb == 'buffers' then
      act_buffers()
    elseif p.verb == 'sidebar' then
      act_sidebar(p.positional[1])
    elseif p.verb == 'mode' then
      act_mode(p.positional[1])
    else
      act_explorer()
    end
  end, {
    nargs    = '*',
    complete = function(arg_lead, line)
      local out
      if line:match('^%s*PKMPanel%s+[Mm][Oo][Dd][Ee]%s') then
        out = { 'on', 'off' }
      elseif line:match('^%s*PKMPanel%s+[Ss][Ii][Dd][Ee][Bb][Aa][Rr]%s') then
        out = require('pkm.views').list()
      else
        out = PANEL_VERBS
      end
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, out)
    end,
    desc = 'Panels: :PKMPanel [explorer] | buffers | sidebar [view] | mode [on|off]',
  })

  -- ---------------------------------------------------------------------------
  -- Aliases
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMBuffers', function()
    act_buffers()
  end, { desc = 'Toggle the persistent bottom buffer-list panel' })

  vim.api.nvim_create_user_command('PKMMode', function(opts)
    act_mode(opts.args)
  end, {
    nargs = '?',
    complete = function() return { 'on', 'off' } end,
    desc = 'Toggle PKM mode (explorer + index + syntax)',
  })

  vim.api.nvim_create_user_command('PKMExplorer', function()
    act_explorer()
  end, { desc = 'Toggle PKM explorer (sidebar + buffer panel)' })

end

return M
