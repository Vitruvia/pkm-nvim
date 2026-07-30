-- =============================================================================
-- pkm.commands.browse — searching and browsing the vault
-- =============================================================================
-- Dependencies : pkm.args, pkm.telescope, pkm.ui, pkm.index, pkm.views,
--                pkm.tags, pkm.utils, pkm.commands.shared (lazy)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Opening notes, reached two ways. `:PKMBrowse <verb>` is the context form the
-- command clearup introduces — a bare filter expression (the default), plus
-- `recent`, `orphans`, and `tags` (browse by tag). The original names
-- (`:PKMBrowseRecent`, `:PKMOrphans`) stay as aliases and drive the same cores.
-- Each falls back from Telescope to the built-in ui when Telescope is absent.
--
-- `tags` is the browse half of `:PKMTags`; the batch half stays on `:PKMTags`
-- (kept as an alias) until the alias-deletion version homes it on `:PKMTag`.
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

--- Browse notes matching a filter expression (or all notes when nil).
local function act_browse(expr)
  focus_main_win()
  if pcall(require, 'telescope') then
    require('pkm.telescope').browse(expr)
  else
    require('pkm.ui').browse(expr)
  end
end

--- The n most recently modified notes.
local function act_recent(n)
  focus_main_win()
  n = n or 20
  if pcall(require, 'telescope') then
    require('pkm.telescope').browse_recent(n)
  else
    require('pkm.ui').browse_recent(n)
  end
end

--- Notes with no tags, no citations, and belonging to no defined view.
local function act_orphans()
  focus_main_win()
  local index = require('pkm.index')
  local views = require('pkm.views')
  local utils = require('pkm.utils')

  -- The set of paths that appear in at least one defined view. match_set reads
  -- the index once for the whole batch.
  local viewed = views.match_set(views.list())

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

  local label = string.format('Orphans (%d)', #orphan_paths)
  if pcall(require, 'telescope') then
    require('pkm.telescope').browse_paths(label, orphan_paths)
  else
    require('pkm.ui').browse_paths(label, orphan_paths)
  end
end

--- Browse notes by tag (the browse half of :PKMTags).
local function act_browse_tags()
  focus_main_win()
  require('pkm.tags').browse_by_tag()
end

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- :PKMBrowse — the context form: [filter] | recent | orphans | tags
  -- ---------------------------------------------------------------------------
  local BROWSE_VERBS = { 'recent', 'orphans', 'tags' }

  vim.api.nvim_create_user_command('PKMBrowse', function(opts)
    local p = require('pkm.args').parse(opts, { verbs = BROWSE_VERBS })
    if p.verb == 'recent' then
      act_recent(tonumber(p.positional[1]))
    elseif p.verb == 'orphans' then
      act_orphans()
    elseif p.verb == 'tags' then
      act_browse_tags()
    else
      -- Default: the whole argument line is a filter expression (or nil for all).
      local expr = opts.args ~= '' and opts.args or nil
      act_browse(expr)
    end
  end, {
    nargs    = '*',
    complete = function(arg_lead, line, pos)
      local out = browse_complete(arg_lead, line, pos) or {}
      -- On the first argument word, the verbs are also candidates.
      local words = vim.split(vim.trim(line), '%s+')
      if #words <= 2 then
        local lead = (arg_lead or ''):lower()
        for i = #BROWSE_VERBS, 1, -1 do
          local v = BROWSE_VERBS[i]
          if v:find(lead, 1, true) == 1 then table.insert(out, 1, v) end
        end
      end
      return out
    end,
    desc = 'Browse notes: :PKMBrowse [<filter>] | recent [n] | orphans | tags',
  })

  -- ---------------------------------------------------------------------------
  -- Aliases
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMBrowseRecent', function(opts)
    act_recent(tonumber(opts.args))
  end, {
    nargs = '?',
    desc  = 'Show the n most recently modified notes (default 20)',
  })

  vim.api.nvim_create_user_command('PKMOrphans', function()
    act_orphans()
  end, { desc = 'Show notes with no tags, no citations, and no matching view' })

end

return M
