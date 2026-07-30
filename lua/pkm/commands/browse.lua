-- =============================================================================
-- pkm.commands.browse — searching and browsing the vault
-- =============================================================================
-- Dependencies : pkm.telescope, pkm.ui, pkm.index, pkm.views, pkm.utils,
--                pkm.commands.shared (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Opening notes by filter, by recency, or by being orphaned. Each falls back
-- from Telescope to the built-in ui when Telescope is not installed.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local focus_main_win = require('pkm.commands.shared').focus_main_win

--- Command-line completion for :PKMBrowse filter expressions.
--- Suggests field prefixes, boolean operators, and 'tag:<value>' completions
--- sourced from the index (if already built).
---@param arg_lead string   Current word being completed
---@return string[]
local function browse_complete(arg_lead, _cmd_line, _cursor_pos)
  local keywords = {
  'AND', 'OR', 'NOT',
  'tag:', 'title:', 'text:', 'filename:', 'any:', 'type:',
  }

  -- After 'tag:' prefix: suggest 'tag:<known-tag>' candidates.
  local tag_stub = arg_lead:match('^tag:(.*)$')
  if tag_stub ~= nil then
    local index = require('pkm.index')
    if not index.is_built() then return {} end
    local seen, out = {}, {}
    local stub_lower = tag_stub:lower()
    for _, e in ipairs(index.get_all()) do
      for _, t in ipairs(e.tags or {}) do
        if not seen[t] and t:find(stub_lower, 1, true) then
          seen[t] = true
          out[#out + 1] = 'tag:' .. t
        end
      end
    end
    table.sort(out)
    return out
  end

  local type_stub = arg_lead:match('^type:(.*)$')
  if type_stub ~= nil then
    local types = { 'note', 'agg', 'bib', 'journal', 'scratch', 'other' }
    local out = {}
    for _, t in ipairs(types) do
      if t:find(type_stub, 1, true) then out[#out + 1] = 'type:' .. t end
    end
    return out
  end

  -- General: filter all static tokens by the current arg_lead.
  local lead_lower = arg_lead:lower()
  local out = {}
  for _, tok in ipairs(keywords) do
    if tok:lower():find(lead_lower, 1, true) then
      out[#out + 1] = tok
    end
  end
  return out
end

local M = {}

function M.register()

  vim.api.nvim_create_user_command('PKMBrowse', function(opts)
    focus_main_win()
    local expr = opts.args ~= '' and opts.args or nil
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').browse(expr)
    else
      require('pkm.ui').browse(expr)
    end
  end, {
    nargs    = '*',
    complete = browse_complete,
    desc     = 'Browse PKM notes with optional filter expression (tag:x AND title:y etc.)',
  })

  vim.api.nvim_create_user_command('PKMBrowseRecent', function(opts)
    focus_main_win()
    local n = tonumber(opts.args) or 20
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').browse_recent(n)
    else
      require('pkm.ui').browse_recent(n)
    end
  end, {
    nargs = '?',
    desc  = 'Show the n most recently modified notes (default 20)',
  })

  vim.api.nvim_create_user_command('PKMOrphans', function()
    focus_main_win()
    local index = require('pkm.index')
    local views = require('pkm.views')
    local utils = require('pkm.utils')

    -- The set of paths that appear in at least one defined view. match_set
    -- reads the index once for the whole batch; the match_all loop this
    -- replaces read it once per view and sorted each result by basename, an
    -- order a membership test cannot use.
    local viewed = views.match_set(views.list())

    -- An orphan has no tags, no citations, and belongs to no view.
    local orphan_paths = {}
    for _, e in ipairs(index.get_all()) do
      if (not e.has_citations)
      and (#(e.tags or {}) == 0)
      and (not viewed[utils.normalize(e.path)]) then
        orphan_paths[#orphan_paths + 1] = e.path
      end
    end

    if #orphan_paths == 0 then
      vim.notify('[pkm] no orphaned notes', vim.log.levels.INFO)
      return
    end

    local label    = string.format('Orphans (%d)', #orphan_paths)
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').browse_paths(label, orphan_paths)
    else
      require('pkm.ui').browse_paths(label, orphan_paths)
    end
  end, { desc = 'Show notes with no tags, no citations, and no matching view' })

end

return M
