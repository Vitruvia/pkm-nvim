-- =============================================================================
-- pkm.commands.syntax — toggle PKM markdown highlighting on the current buffer
-- =============================================================================
-- Dependencies : pkm.args, pkm.syntax (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- `:PKMSyntax [on|off|toggle]` — the manual on/off control for PKM highlighting,
-- independent of PKM mode and the `highlight_all_markdown` config. Bare = toggle.
-- A PKM note (under the vault root) is enabled with the full note look (fold +
-- window options); any other markdown gets the pure highlighting (highlight_only),
-- so this never applies note behaviour to an unrelated file.
--
-- Public API:
--   register() → register this context's :PKM* command
-- =============================================================================

--- Is this buffer a note under the active vault root? Mirrors the root check in
--- mode.lua's syntax_enable_all — a buffer under root gets the full note look.
---@param bufnr integer
---@return boolean
local function is_pkm_buffer(bufnr)
  local root = require('pkm').config.root_path:gsub('\\', '/'):gsub('[/\\]+$', '')
  local name = vim.api.nvim_buf_get_name(bufnr):gsub('\\', '/')
  return name ~= '' and name:lower():sub(1, #root + 1) == root:lower() .. '/'
end

--- Enable PKM highlighting on a buffer, choosing full vs highlight-only by whether
--- it is a vault note.
---@param bufnr integer
local function turn_on(bufnr)
  require('pkm.syntax').enable(bufnr, not is_pkm_buffer(bufnr))
end

local M = {}

function M.register()
  local SYNTAX_VERBS = { 'on', 'off', 'toggle' }

  vim.api.nvim_create_user_command('PKMSyntax', function(opts)
    local p      = require('pkm.args').parse(opts, { verbs = SYNTAX_VERBS })
    local syntax = require('pkm.syntax')
    local buf    = vim.api.nvim_get_current_buf()
    local verb   = p.verb or 'toggle'

    if verb == 'on' then
      turn_on(buf)
    elseif verb == 'off' then
      syntax.disable(buf)
    else   -- toggle
      if syntax.is_active(buf) then syntax.disable(buf) else turn_on(buf) end
    end
  end, {
    nargs    = '?',
    complete = function(arg_lead)
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(
        function(t) return t:lower():find(lead, 1, true) == 1 end, SYNTAX_VERBS)
    end,
    desc = 'Highlighting: :PKMSyntax [on|off|toggle] (bare = toggle) on the current buffer',
  })
end

return M
