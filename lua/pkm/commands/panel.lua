-- =============================================================================
-- pkm.commands.panel — the persistent panels and PKM mode toggles
-- =============================================================================
-- Dependencies : pkm.args, pkm.ui, pkm.views, pkm.mode (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- The panels and mode toggles. `:PKMPanel <verb>` — `explorer` (the default:
-- sidebar + buffer panel as a unit), `buffers`, `sidebar`, `mode`. `sidebar`
-- opens the view sidebar (also reachable as `:PKMView sidebar`).
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

--- Toggle the bottom buffer-list panel.
local function act_buffers()
  require('pkm.ui').toggle_bufpanel()
end

--- Toggle the current-file navigation panel (heading index of the focused note).
local function act_nav()
  require('pkm.nav').toggle()
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
  local PANEL_VERBS = { 'explorer', 'buffers', 'nav', 'sidebar', 'mode' }

  vim.api.nvim_create_user_command('PKMPanel', function(opts)
    local p = require('pkm.args').parse(opts, { verbs = PANEL_VERBS, default = 'explorer' })
    if p.verb == 'buffers' then
      act_buffers()
    elseif p.verb == 'nav' then
      act_nav()
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
    desc = 'Panels: :PKMPanel [explorer] | buffers | nav | sidebar [view] | mode [on|off]',
  })

end

return M
