-- =============================================================================
-- pkm.actions — Bulk actions over a set of notes
-- =============================================================================
-- Dependencies : pkm.tags (lazy), pkm.rename (lazy)
-- Consumed by  : pkm.telescope (live_picker <C-a>), pkm.views (views panel <C-a>)
--
-- One registry, one entry point. A navigation panel already knows how to choose
-- notes; what it lacked was a way to *do* something with them. `run(paths)`
-- takes whatever the panel selected and offers the operations that act on a set
-- of notes — nothing else in this module knows about panels, and no panel knows
-- about tags.
--
-- The registry is a plain list of `{ id, label, run }`. Growing the menu means
-- appending an entry here, not touching a panel again: view membership and bulk
-- rename land as two more rows in later phases.
--
-- Layering, per the command-surface policy (ROADMAP § Command clearup): the
-- registry is data — `list()` is pure and enumerable, which is what will let the
-- future `pkm.api` expose these operations without a UI. The menu in `run()` is
-- the only interactive part, and each action opens its own screens from there.
--
-- Public API:
--   list()             → the registry, in menu order (pure)
--   get(id)            → one action by id, or nil (pure)
--   run(paths, opts?)  → menu over list(), then dispatch to the chosen action
--   run_id(id, paths)  → dispatch straight to one action, no menu
-- =============================================================================

local M = {}

-- =============================================================================
-- SECTION: Registry
-- =============================================================================

--- Bulk actions, in the order the menu shows them.
--- `run` receives the selected paths and a context table, and owns every screen
--- it needs from there. `ctx.on_back` reopens whatever chose these notes — the
--- browser, the view, the panel — so an action can offer a way out that lands
--- where the user actually came from rather than on a narrowed copy of it.
--- `ctx.view` is the view the notes were chosen from, when there was one: a
--- view action then never asks which view, because the editor already knows.
---@type { id: string, label: string, run: fun(paths: string[], ctx: table) }[]
local REGISTRY = {
  {
    id    = 'tag_add',
    label = 'Add a tag',
    run   = function(paths) require('pkm.tags').batch_on(paths, 'add') end,
  },
  {
    id    = 'tag_remove',
    label = 'Remove a tag',
    run   = function(paths) require('pkm.tags').batch_on(paths, 'remove') end,
  },
  {
    id    = 'tag_rename',
    label = 'Rename a tag',
    run   = function(paths) require('pkm.tags').batch_on(paths, 'rename') end,
  },
  {
    id    = 'set_titles',
    label = 'Change the title',
    run   = function(paths, ctx) require('pkm.rename').title_flow(paths, ctx) end,
  },
  {
    id    = 'rename_files',
    label = 'Rename the file',
    run   = function(paths, ctx) require('pkm.rename').filename_flow(paths, ctx) end,
  },
  {
    id    = 'view_add',
    label = 'Add to a view',
    run   = function(paths, ctx) require('pkm.tags').view_flow(paths, 'add', ctx) end,
  },
  {
    id    = 'view_remove',
    label = 'Remove from a view',
    run   = function(paths, ctx) require('pkm.tags').view_flow(paths, 'remove', ctx) end,
  },
}

-- =============================================================================
-- SECTION: Public API
-- =============================================================================

--- Every registered bulk action, in menu order.
--- Returns the live registry table; callers read it, they do not mutate it.
---@return { id: string, label: string, run: function }[]
function M.list()
  return REGISTRY
end

--- Look one action up by id.
---@param id string
---@return { id: string, label: string, run: function }|nil
function M.get(id)
  for _, action in ipairs(REGISTRY) do
    if action.id == id then return action end
  end
  return nil
end

--- Run one action by id over a set of notes, skipping the menu.
--- The programmatic entry point: no screen of its own, so it is what a keymap,
--- a command argument, or a headless caller can reach for.
---@param id    string
---@param paths string[]
---@param ctx   table|nil  { on_back? = function }
---@return boolean ok  false when the id is unknown or there are no notes
function M.run_id(id, paths, ctx)
  local action = M.get(id)
  if not action then
    vim.notify('[pkm] unknown action: ' .. tostring(id), vim.log.levels.ERROR)
    return false
  end
  if not paths or #paths == 0 then
    vim.notify('[pkm] no notes selected', vim.log.levels.INFO)
    return false
  end

  action.run(paths, ctx or {})
  return true
end

--- Offer the bulk actions for a set of notes and run the chosen one.
--- The menu is a small fixed choice set, so it stays `vim.ui.select` — the same
--- criterion as the Simple/Deep menu of `:PKMExport`.
---@param paths string[]  The notes the action will act on
---@param opts  table|nil { prompt? = string, on_back? = function, view? = string }
function M.run(paths, opts)
  opts = opts or {}

  if not paths or #paths == 0 then
    vim.notify('[pkm] no notes selected', vim.log.levels.INFO)
    return
  end

  local labels = {}
  for _, action in ipairs(REGISTRY) do labels[#labels + 1] = action.label end

  vim.ui.select(labels, {
    prompt = opts.prompt or string.format('Act on %d note%s:',
      #paths, #paths == 1 and '' or 's'),
  }, function(_, idx)
    -- Backing out of the menu returns where the notes came from, when the
    -- caller said how.
    if not idx then
      if opts.on_back then vim.schedule(opts.on_back) end
      return
    end
    local action = REGISTRY[idx]
    if action then
      vim.schedule(function()
        action.run(paths, { on_back = opts.on_back, view = opts.view })
      end)
    end
  end)
end

return M
