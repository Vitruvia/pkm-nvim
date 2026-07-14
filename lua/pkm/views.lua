-- =============================================================================
-- pkm.views — Named project views over the note index
-- =============================================================================
-- Dependencies : pkm.filter, pkm.index (lazy), pkm.utils
-- Consumed by  : pkm.commands (:PKMView, :PKMViews, :PKMViewNew,
--                :PKMViewEdit, :PKMViewDelete)
--                pkm.init (setup, delete_note_safely)
--
-- A view is a named filter expression. Views are stored in views.json at the
-- PKM root and optionally in config.projects. The sidecar file takes
-- precedence over config on name collision.
--
-- views.json lives alongside notes and can be version-controlled with them.
-- It requires no Neovim config changes to add, edit, or remove views.
--
-- views.json format (string = simple view; table = subproject):
--   {
--     "rpg":    "tag:rpg AND (title:ringforge OR text:ringforge)",
--     "ringforge-mechanics": {
--       "parent": "ringforge",
--       "filter": "tag:mechanics"
--     }
--   }
--
-- Loading order:
--   config.projects  →  base definitions (optional, declared in Lazy config)
--   views.json       →  overrides config on name collision
--
-- Caches are invalidated automatically when views.json is saved from inside
-- Neovim via a BufWritePost autocmd registered in setup(). External edits
-- are picked up on the next access after the cache is stale.
--
-- Public API:
--   setup()             → register BufWritePost autocmd for views.json
--   list()              → string[]  sorted view names (sidecar + config)
--   open_views_panel(mode?)  → browse/create/update views; Telescope when
--                               available (live search), panel.lua fallback
--                               otherwise. <C-f> jumps to browse-all-notes
--                               from either backend, either level (tree or
--                               a specific view's detail).
--   open_view_deletion_panel() → browse/select/confirm-delete a view (Phase 3)
--   set_panel_keymap(lhs)    → set the optional sidebar→views-panel key
--   edit_view(name?)    → action picker: edit filter / rename / reparent; picker if nil
--   match_all(name)     → string[]  paths matching the named view's filter
--   open(name?)         → activate a view; prompts for name if nil
--   open_last()         → reopen the last activated view (session-scoped)
--   get_last_view()     → active view name for context-aware features (sidebar > last)
--   open_sidebar(name?) → open/toggle persistent sidebar (per-tabpage; no cross-tab conflict)
--   is_sidebar_open()   → boolean, whether sidebar is open in current tabpage
--   get_sidebar_win()   → integer|nil, sidebar window handle or nil
--   refresh_sidebar_if_open() → refresh sidebar in all open tabpages
--   save(name, expr)    → write or update a view in views.json
--   save_subproject(name, parent, filter_expr) → write a subproject entry to views.json
--   delete(name)        → remove a view from views.json
-- =============================================================================

local M = {}

local utils = require('pkm.utils')
local panel = require('pkm.panel')

-- =============================================================================
-- SECTION: State
-- =============================================================================

local _sidecar_cache = nil   -- table loaded from views.json; nil when stale
local _tree_cache    = {}    -- name → parsed filter tree
local _last_view = nil          -- name of last successfully activated view
local _panel_keymap_lhs = nil   -- sidebar-buffer-local key to open the views
                                 -- panel; nil until set_panel_keymap() is
                                 -- called from keymaps.lua (opt-in, see config)

-- Per-tabpage sidebar state. Keyed by nvim_get_current_tabpage().
-- Each tab carries its own win, buf, mode, name, paths, tree,
-- header_count, view_lines, and history, eliminating cross-tab conflicts.
local _tabs = {}

--- Return the current tabpage's sidebar state table, creating it if absent.
local function get_tab()
  local id = vim.api.nvim_get_current_tabpage()
  if not _tabs[id] then
    _tabs[id] = {
      win          = nil,
      buf          = nil,
      name         = nil,
      paths        = {},
      tree         = {},
      header_count = 0,
      mode         = nil,
      view_lines   = {},
      history      = {},
      type_filter  = nil,   -- string|nil; filters displayed notes by note_type
    }
  end
  return _tabs[id]
end

local _TYPE_ORDER = { note = 1, agg = 2, bib = 3, journal = 4, scratch = 5,
other = 6 }

local _TYPE_ABBREV = {
  note    = 'n',
  agg     = 'a',
  bib     = 'b',
  journal = 'j',
  scratch = 's',
  other   = 'o',
}

-- =============================================================================
-- SECTION: Internal helpers — config and sidecar
-- =============================================================================

local function get_config()
  return require('pkm').config
end

local function sidecar_path()
  return utils.join(get_config().root_path, 'views.json')
end

--- Load views.json and return its contents as a table.
--- Returns {} if the file is absent or malformed.
local function load_sidecar()
  local path = sidecar_path()
  if vim.fn.filereadable(path) == 0 then return {} end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' then return {} end

  local raw = table.concat(lines, '\n')
  if raw:match('^%s*$') then return {} end

  local ok2, data = pcall(vim.json.decode, raw)
  if not ok2 or type(data) ~= 'table' then
    vim.notify('PKMView: views.json is malformed — ignoring', vim.log.levels.WARN)
    return {}
  end

  return data
end

--- Return merged projects: config.projects merged with sidecar, sidecar wins.
local function get_projects()
  if not _sidecar_cache then
    _sidecar_cache = load_sidecar()
  end

  local merged          = {}
  local config_projects = get_config().projects or {}

  for k, v in pairs(config_projects) do merged[k] = v end
  for k, v in pairs(_sidecar_cache)  do merged[k] = v end  -- sidecar wins

  return merged
end

--- Invalidate sidecar and tree caches.
local function invalidate()
  _sidecar_cache = nil
  _tree_cache    = {}
end

--- Return the parent view name for a subproject, or nil for root views.
---@param name string
---@return string|nil
local function get_view_parent(name)
  local expr = get_projects()[name]
  if type(expr) == 'table' and type(expr.parent) == 'string' then
    return expr.parent
  end
  return nil
end

--- Return sorted names of all views whose parent field equals name.
---@param name string
---@return string[]
local function get_view_children(name)
  local children = {}
  for k, v in pairs(get_projects()) do
    if type(v) == 'table' and v.parent == name then
      children[#children + 1] = k
    end
  end
  table.sort(children, function(a, b) return a:lower() < b:lower() end)
  return children
end

--- Build a depth-first ordered list of all views for tree display.
--- Root views (no parent, or parent not in projects) come first, sorted.
--- Each entry carries name, depth, and whether it has children.
---@return table[]  Array of {name=string, depth=integer, has_children=boolean}
local function build_tree_entries()
  local projects     = get_projects()
  local children_map = {}

  for name, expr in pairs(projects) do
    local parent = type(expr) == 'table'
                   and type(expr.parent) == 'string'
                   and projects[expr.parent] ~= nil
                   and expr.parent or nil
    if parent then
      children_map[parent] = children_map[parent] or {}
      children_map[parent][#children_map[parent] + 1] = name
    end
  end

  -- Case-insensitive: a raw sort puts any uppercase-starting name (e.g.
  -- "Zebra", byte 0x5A) before an underscore-prefixed one ("_meta", byte
  -- 0x5F), which reads as wrong once you expect underscore-prefixed
  -- meta/reference views to sort first (Design Questions decision 2).
  -- Lowercasing both sides neutralizes case, and '_' (0x5F) already sorts
  -- before any lowercase letter (0x61+), so this achieves both at once.
  for _, children in pairs(children_map) do
    table.sort(children, function(a, b) return a:lower() < b:lower() end)
  end

  local roots = {}
  for name, expr in pairs(projects) do
    local has_parent = type(expr) == 'table'
                       and type(expr.parent) == 'string'
                       and projects[expr.parent] ~= nil
    if not has_parent then roots[#roots + 1] = name end
  end
  table.sort(roots, function(a, b) return a:lower() < b:lower() end)

  local entries = {}
  local function visit(name, depth)
    entries[#entries + 1] = {
      name         = name,
      depth        = depth,
      has_children = children_map[name] ~= nil,
    }
    for _, child in ipairs(children_map[name] or {}) do
      visit(child, depth + 1)
    end
  end
  for _, root in ipairs(roots) do visit(root, 0) end

  return entries
end

--- Sort a path list by note type (note→agg→bib→journal→scratch) then title.
---@param paths string[]
---@return string[]  New sorted array
local function sort_paths_by_type(paths)
  local index  = require('pkm.index')
  local sorted = vim.list_extend({}, paths)
  table.sort(sorted, function(a, b)
    local ea = index.get(a)
    local eb = index.get(b)
    local ta = ea and (_TYPE_ORDER[ea.note_type] or 6) or 6
    local tb = eb and (_TYPE_ORDER[eb.note_type] or 6) or 6
    if ta ~= tb then return ta < tb end
    local ta_t = (ea and ea.title or vim.fn.fnamemodify(a, ':t:r')):lower()
    local tb_t = (eb and eb.title or vim.fn.fnamemodify(b, ':t:r')):lower()
    return ta_t < tb_t
  end)
  return sorted
end

--- Pure: sort a list of {win, col} entries by column position, ascending
--- (left to right). Used by both N<CR> and <C-v> to establish a
--- consistent left-to-right editing-window order — extracted so both
--- share one tested implementation rather than duplicating the sort.
---@param entries {win:integer, col:integer}[]
---@return {win:integer, col:integer}[]  New sorted array
local function sort_wins_by_col(entries)
  local sorted = vim.list_extend({}, entries)
  table.sort(sorted, function(a, b) return a.col < b.col end)
  return sorted
end

--- Pure: resolve a [count]<CR> request against the number of available
--- editing windows. Returns nil for "do nothing" (n<=0, or n exceeds the
--- available count) rather than creating a window — see the Phase 3
--- design note: auto-creating on overflow was reconsidered and dropped,
--- since N<CR> is a high-frequency action and a miscounted N silently
--- altering the window layout is worse than a no-op with a message.
---@param n integer  Requested window number (vim.v.count)
---@param available_count integer  Number of real editing windows
---@return integer|nil  1-indexed window number to target, or nil if out of range
local function resolve_window_slot(n, available_count)
  if n <= 0 then return nil end
  if n > available_count then return nil end
  return n
end

--- Pure: decide which window a relative-split picker action should target.
--- The invocation window is captured (by the caller) at the moment the
--- picker was opened, before any selection happened.
---@param direction 'left'|'right'
---@param invocation_was_sidebar boolean  Was the invocation window pkm-sidebar at capture time?
---@param invocation_still_valid boolean  Does the invocation window still exist?
---@return 'invocation'|'rightmost'|nil  Which window to target, or nil for "unavailable, do nothing"
local function resolve_split_target(direction, invocation_was_sidebar, invocation_still_valid)
  if direction == 'left' then
    if invocation_was_sidebar then return nil end
    if not invocation_still_valid then return nil end
    return 'invocation'
  else -- 'right'
    if invocation_still_valid then return 'invocation' end
    return 'rightmost'
  end
end

--- Open target_path in a vertical split relative to invocation_win, the
--- window that was current when the picker containing this action was
--- opened (captured once, before any selection). 'left' is unavailable
--- when the invocation window was the sidebar (nothing to its left) or no
--- longer exists; 'right' falls back to the rightmost real editing window
--- if the invocation window is gone. Explicit leftabove/rightbelow (never
--- a bare vsplit) so this is deterministic regardless of 'splitright'.
---@param direction 'left'|'right'
---@param target_path string
---@param invocation_win integer|nil
---@param invocation_was_sidebar boolean
local function open_relative_split(direction, target_path, invocation_win, invocation_was_sidebar)
  local invocation_still_valid = invocation_win ~= nil
    and vim.api.nvim_win_is_valid(invocation_win)
  local strategy = resolve_split_target(direction, invocation_was_sidebar, invocation_still_valid)

  if strategy == nil then
    vim.notify('[pkm] no left split available here', vim.log.levels.INFO)
    return
  end

  local target_win
  if strategy == 'invocation' then
    target_win = invocation_win
  else -- 'rightmost'
    local _PANELS = { ['pkm-sidebar'] = true, ['pkm-bufpanel'] = true, ['netrw'] = true }
    local candidates = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).relative == '' then
        if not _PANELS[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
          candidates[#candidates + 1] = { win = win, col = vim.api.nvim_win_get_position(win)[2] }
        end
      end
    end
    if #candidates == 0 then
      vim.cmd('rightbelow vsplit ' .. vim.fn.fnameescape(target_path))
      return
    end
    local sorted = sort_wins_by_col(candidates)
    target_win = sorted[#sorted].win
  end

  vim.api.nvim_set_current_win(target_win)
  if direction == 'left' then
    vim.cmd('leftabove vsplit ' .. vim.fn.fnameescape(target_path))
  else
    vim.cmd('rightbelow vsplit ' .. vim.fn.fnameescape(target_path))
  end
end

--- Push current sidebar state onto the navigation history stack.
--- Capped at 50 entries; oldest entry dropped when full.
local function sidebar_push_history()
  local t = get_tab()
  if not t.mode then return end
  if #t.history >= 50 then table.remove(t.history, 1) end
  t.history[#t.history + 1] = { mode = t.mode, name = t.name }
end

--- Pop the most recent sidebar state from the history stack.
---@return table|nil  {mode=string, name=string|nil} or nil if empty
local function sidebar_pop_history()
  local t = get_tab()
  if #t.history == 0 then return nil end
  local state = t.history[#t.history]
  t.history[#t.history] = nil
  return state
end

--- Format a note type as a fixed-width bracket label for display alignment.
---@param note_type string
---@return string  e.g. "[note   ]" or "[journal]"
local function type_prefix(note_type)
  return '[' .. (_TYPE_ABBREV[note_type or 'other'] or 'o') .. ']'
end

--- Strip the leading note-number and type prefix from a filename stem.
--- "0042_note_Title_Words"      → "Title_Words"
--- "journal_2026-06-17_10-30"  → "2026-06-17_10-30"
--- "scratch_2026-06-17_10-30"  → "2026-06-17_10-30"
--- Unknown conventions: returned unchanged.
---@param filename  string  Index `filename` field (stem, no extension)
---@param note_type string
---@return string
local function strip_display_prefix(filename, note_type)
  if note_type == 'journal' or note_type == 'scratch' then
    return filename:match('^%a+_(.+)$') or filename
  elseif note_type == 'note' or note_type == 'agg' or note_type == 'bib' then
    return filename:match('^%d+_%a+_(.+)$') or filename
  end
  return filename
end

--- Sort a path list by modification time, most recent first.
---@param paths string[]
---@return string[]
local function sort_paths_by_mtime(paths)
  local index  = require('pkm.index')
  local sorted = vim.list_extend({}, paths)
  table.sort(sorted, function(a, b)
    local ea = index.get(a)
    local eb = index.get(b)
    return (ea and ea.mtime or 0) > (eb and eb.mtime or 0)
  end)
  return sorted
end

--- Parse and cache the filter tree for a named view.
--- Handles string expressions (simple views) and table values
--- (subprojects: {parent=string, filter=string}). Detects cycles.
---@param name    string
---@param _visited table|nil  Internal cycle-detection set; do not pass
---@return table|nil tree
---@return string|nil err
local function get_tree(name, _visited)
  if _tree_cache[name] then return _tree_cache[name], nil end

  _visited = _visited or {}
  if _visited[name] then
    return nil, string.format(
      "PKMView: cycle detected in view hierarchy at '%s'", name)
  end
  if vim.tbl_count(_visited) >= 8 then
    return nil, string.format(
      "PKMView: hierarchy depth limit (8) reached at '%s'", name)
  end

  local projects = get_projects()
  if not projects[name] then
    return nil, string.format("PKMView: no view named '%s'", name)
  end

  _visited[name] = true
  local expr   = projects[name]
  local filter = require('pkm.filter')
  local tree, err

  if type(expr) == 'string' then
    if expr:match('^%s*$') then
      return nil, string.format(
        "PKMView: view '%s' has an empty filter expression", name)
    end
    tree, err = filter.parse(expr)
    if not tree then
      return nil, string.format(
        "PKMView: parse error in view '%s': %s", name, err)
    end

  elseif type(expr) == 'table' then
    local parent_name = expr.parent
    local sub_filter  = expr.filter

    if type(parent_name) ~= 'string' or parent_name == '' then
      return nil, string.format(
        "PKMView: subproject '%s' missing valid 'parent' field", name)
    end
    if type(sub_filter) ~= 'string' or sub_filter:match('^%s*$') then
      return nil, string.format(
        "PKMView: subproject '%s' missing valid 'filter' field", name)
    end

    local parent_tree, parent_err = get_tree(parent_name, _visited)
    if not parent_tree then
      return nil, string.format(
        "PKMView: error resolving parent '%s' for '%s': %s",
        parent_name, name, parent_err)
    end

    local sub_tree, sub_err = filter.parse(sub_filter)
    if not sub_tree then
      return nil, string.format(
        "PKMView: parse error in subproject '%s': %s", name, sub_err)
    end

    tree = { type = 'AND', args = { parent_tree, sub_tree } }
  else
    return nil, string.format(
      "PKMView: view '%s' must be a string or a {parent, filter} table", name)
  end

  _tree_cache[name] = tree
  return tree, nil
end

--- Write a views table to views.json in human-readable form.
--- Keys are sorted alphabetically; one entry per line.
---@param data table
---@return boolean success
local function save_sidecar(data)
  local path = sidecar_path()
  local keys = vim.tbl_keys(data)
  table.sort(keys)

  local lines = { '{' }
  for i, k in ipairs(keys) do
    local comma = i < #keys and ',' or ''
    lines[#lines + 1] = string.format('  %s: %s%s',
      vim.json.encode(k), vim.json.encode(data[k]), comma)
  end
  lines[#lines + 1] = '}'

  local ok, err = pcall(vim.fn.writefile, lines, path)
  if not ok then
    vim.notify('PKMView: failed to write views.json — ' .. (err or ''), vim.log.levels.ERROR)
    return false
  end

  -- Invalidate immediately; the BufWritePost autocmd will also fire if the
  -- file is open in a buffer, but we invalidate here too for safety.
  invalidate()
  return true
end

-- =============================================================================
-- SECTION: Setup
-- =============================================================================

--- Register the BufWritePost autocmd that invalidates caches when views.json
--- is saved from inside Neovim. Must be called from pkm.init.setup().
function M.setup()
  local augroup = vim.api.nvim_create_augroup('PKMViews', { clear = true })

  -- Subprojects (parent-bearing entries) are only ever valid in views.json.
  -- config.lua is Lua source, not a data file the plugin can safely rewrite,
  -- so a subproject defined there would go silently stale on any rename —
  -- there would be no way to keep it in sync. Enforced here rather than
  -- left as a rename-time warning: under normal use config.projects should
  -- never contain one at all.
  local bad = {}
  for k, v in pairs(get_config().projects or {}) do
    if type(v) == 'table' and v.parent then
      bad[#bad + 1] = k
    end
  end
  if #bad > 0 then
    table.sort(bad)
    vim.notify(
      string.format(
        "[pkm] config.lua 'projects' has subproject(s) with a 'parent' field: %s — move to views.json via :PKMViewNewSub; config-defined subprojects cannot be renamed correctly",
        table.concat(bad, ', ')),
      vim.log.levels.WARN)
  end

  vim.api.nvim_create_autocmd('BufWritePost', {
    group    = augroup,
    pattern  = 'views.json',
    callback = function()
      local written  = vim.fn.expand('<afile>:p'):gsub('\\', '/')
      local root     = get_config().root_path:gsub('\\', '/')
      local expected = root:gsub('[/\\]+$', '') .. '/views.json'
      if written:lower() == expected:lower() then
        invalidate()
        vim.notify('PKMView: views reloaded from views.json', vim.log.levels.INFO)
      end
    end,
  })

  vim.api.nvim_create_autocmd('TabClosed', {
    group    = augroup,
    callback = function()
      local live = {}
      for _, tp in ipairs(vim.api.nvim_list_tabpages()) do live[tp] = true end
      for id in pairs(_tabs) do
        if not live[id] then _tabs[id] = nil end
      end
    end,
  })

  -- winfixwidth only stops the sidebar being squeezed when a sibling
  -- window grows — it does nothing when a sibling closes (nothing left
  -- to reassert against) or when a *new* window appears afterward and
  -- inherits whatever proportions existed at that moment. WinResized
  -- fires after any layout change in the tabpage, covering both cases,
  -- so the sidebar only ever changes size via config or an explicit
  -- keymap, never as a side effect of windows opening or closing.
  vim.api.nvim_create_autocmd('WinResized', {
    group    = augroup,
    callback = function()
      vim.schedule(function()
        local width = (require('pkm').config.sidebar_width or 40)
        for _, id in ipairs(vim.api.nvim_list_tabpages()) do
          local t = _tabs[id]
          if t and t.win and vim.api.nvim_win_is_valid(t.win) then
            pcall(vim.api.nvim_win_set_width, t.win, width)
          end
        end
      end)
    end,
  })
end

-- =============================================================================
-- SECTION: Public API — read
-- =============================================================================

--- Return a sorted list of all view names (sidecar + config.projects merged).
---@return string[]
function M.list()
  local names = vim.tbl_keys(get_projects())
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

--- Return all note paths matching the named view's filter expression.
--- Returns an empty array and notifies on error.
---@param name string
---@return string[]  Sorted array of absolute paths
function M.match_all(name)
  local tree, err = get_tree(name)
  if not tree then
    vim.notify(err, vim.log.levels.ERROR)
    return {}
  end

  local filter  = require('pkm.filter')
  local entries = require('pkm.index').get_all()
  local matched = {}

  for _, entry in ipairs(entries) do
    if filter.eval(tree, entry) then
      matched[#matched + 1] = entry.path
    end
  end

  table.sort(matched, function(a, b)
    return vim.fn.fnamemodify(a, ':t') < vim.fn.fnamemodify(b, ':t')
  end)

  return matched
end

--- Return the currently active view name for context-aware features.
--- Prefers the sidebar's open detail view; falls back to the last activated view.
---@return string|nil
function M.get_last_view()
  local t = get_tab()
  if t.win and vim.api.nvim_win_is_valid(t.win)
  and t.mode == 'detail' and t.name then
    return t.name
  end
  return _last_view
end

--- Return true if the sidebar is currently open in the current tabpage.
---@return boolean
function M.is_sidebar_open()
  local t = get_tab()
  return t.win ~= nil and vim.api.nvim_win_is_valid(t.win)
end

--- Return the sidebar window handle for the current tabpage, or nil if closed.
---@return integer|nil
function M.get_sidebar_win()
  local t = get_tab()
  if t.win and vim.api.nvim_win_is_valid(t.win) then return t.win end
  return nil
end

--- Set the sidebar-buffer-local key that opens the views panel. Called
--- once from keymaps.lua during registration; nil/unset means no key is
--- bound (the sidebar's own overview mode remains the only in-sidebar
--- view browsing until this is configured).
---@param lhs string|nil
function M.set_panel_keymap(lhs)
  _panel_keymap_lhs = lhs
end

-- =============================================================================
-- SECTION: Public API — write
-- =============================================================================

--- Add or replace a named view in views.json.
--- Validates the filter expression before writing.
---@param name string
---@param expr string
---@return boolean success
function M.save(name, expr)
  local _, err = require('pkm.filter').parse(expr)
  if err then
    vim.notify('PKMView: invalid expression — ' .. err, vim.log.levels.ERROR)
    return false
  end

  local data = load_sidecar()
  data[name] = expr
  local ok   = save_sidecar(data)
  if ok then
    vim.notify(string.format("PKMView: saved view '%s'", name), vim.log.levels.INFO)
    M.refresh_sidebar_if_open()
  end
  return ok
end

--- Add or replace a subproject view in views.json.
--- Validates that the parent exists and the filter expression is valid.
--- The effective filter is the parent's filter AND-ed with filter_expr;
--- the parent chain is composed automatically at query time.
---@param name        string  New subproject name
---@param parent      string  Existing view name to use as parent
---@param filter_expr string  Own additional filter expression
---@return boolean success
function M.save_subproject(name, parent, filter_expr)
  local projects = get_projects()
  if not projects[parent] then
    vim.notify(
      string.format("PKMViewNewSub: no view named '%s'", parent),
      vim.log.levels.ERROR)
    return false
  end

  local _, err = require('pkm.filter').parse(filter_expr)
  if err then
    vim.notify('PKMViewNewSub: invalid filter — ' .. err, vim.log.levels.ERROR)
    return false
  end

  local data = load_sidecar()
  data[name] = { parent = parent, filter = filter_expr }
  local ok   = save_sidecar(data)
  if ok then
    vim.notify(
      string.format("PKMView: saved subproject '%s' under '%s'", name, parent),
      vim.log.levels.INFO)
    M.refresh_sidebar_if_open()
  end
  return ok
end

--- Remove a named view from views.json.
--- Config-only views cannot be deleted this way.
---@param name string
---@return boolean success
function M.delete(name)
  local data = load_sidecar()
  if not data[name] then
    local in_config = (get_config().projects or {})[name]
    if in_config then
      vim.notify(
        string.format(
          "PKMView: '%s' is defined in your Neovim config, not views.json. Remove it there.",
          name),
        vim.log.levels.WARN)
    else
      vim.notify(string.format("PKMView: no view named '%s'", name), vim.log.levels.WARN)
    end
    return false
  end

  data[name] = nil
  local ok   = save_sidecar(data)
  if ok then
    vim.notify(string.format("PKMView: deleted view '%s'", name), vim.log.levels.INFO)
  end
  return ok
end

-- =============================================================================
-- SECTION: Pickers
-- =============================================================================

--- Telescope picker over pre-matched note paths. Exact substring prompt.
local function telescope_view_picker(name, paths, invocation_win, invocation_was_sidebar)
  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers   = require('telescope.previewers')
  local sorters      = require('telescope.sorters')
  local index        = require('pkm.index')

  local children = get_view_children(name)
  local sorted   = sort_paths_by_type(paths)
  local entries  = {}

  -- Subview entries first (shown at top with ascending sort)
  for _, child in ipairs(children) do
    local c_count = #M.match_all(child)
    entries[#entries + 1] = {
      value      = child,
      display    = string.format('[v] %s  (%d notes)', child, c_count),
      ordinal    = string.format('%05d', #entries + 1),
      is_subview = true,
    }
  end

  -- Note entries
  for _, path in ipairs(sorted) do
    local e         = index.get(path)
    local note_type = e and e.note_type or 'other'
    local title     = e and e.title or vim.fn.fnamemodify(path, ':t:r')
    entries[#entries + 1] = {
      value   = path,
      display = type_prefix(note_type) .. ' ' .. title,
      ordinal = string.format('%05d', #entries + 1),
    }
  end

  local total = #sorted + #children
  pickers.new({
    sorting_strategy = 'ascending',
    layout_config    = { prompt_position = 'top' },
  }, {
    prompt_title = string.format(
      'PKMView: %s  (%d note%s)  <C-b> views  <C-p> parent  <C-s> subs  <C-f> browse all  <C-v>/<C-x> split',
      name, total, total == 1 and '' or 's'),

    finder = finders.new_dynamic({
    fn = function(prompt)
        if not prompt or prompt == '' then return entries end
        local needle = prompt:lower()
        local filtered = {}
        for _, e in ipairs(entries) do
          if e.display:lower():find(needle, 1, true) then
            filtered[#filtered + 1] = e
          end
        end
        return filtered
      end,
      entry_maker = function(e) return e end,
    }),

    sorter    = sorters.Sorter:new({ scoring_function = function() return 0 end }),
    previewer = previewers.vim_buffer_cat.new({}),

    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not entry then return end
        if entry.is_subview then
          vim.schedule(function() M.open(entry.value) end)
        else
          vim.cmd('edit ' .. vim.fn.fnameescape(entry.value))
        end
      end)

      local function go_back()
        actions.close(prompt_bufnr)
        vim.schedule(function() M.open_views_panel() end)
      end

      local function go_parent()
        local parent = get_view_parent(name)
        if parent then
          actions.close(prompt_bufnr)
          vim.schedule(function() M.open(parent) end)
        else
          vim.notify('[pkm] this view has no parent', vim.log.levels.INFO)
        end
      end

      local function go_children()
        local ch = get_view_children(name)
        if #ch == 0 then
          vim.notify('[pkm] this view has no subviews', vim.log.levels.INFO)
          return
        end
        actions.close(prompt_bufnr)
        vim.schedule(function()
          vim.ui.select(ch, {
            prompt      = string.format("Subviews of '%s':", name),
            format_item = function(n)
              return string.format('%s  (%d)', n, #M.match_all(n))
            end,
          }, function(sel) if sel then M.open(sel) end end)
        end)
      end

      local function go_browse()
        actions.close(prompt_bufnr)
        vim.schedule(function() M.open_views_panel('browse') end)
      end

      -- <C-v>/<C-x>: open the selected note in a split right/left of the
      -- invocation window (the window this picker was opened from). Only
      -- meaningful for note entries -- selecting a subview opens another
      -- picker, not a file, so there's nothing to split.
      local function do_split(direction)
        local entry = action_state.get_selected_entry()
        if not entry or entry.is_subview then return end
        actions.close(prompt_bufnr)
        vim.schedule(function()
          open_relative_split(direction, entry.value, invocation_win, invocation_was_sidebar)
        end)
      end

      map('i', '<C-b>', go_back)
      map('n', '<C-b>', go_back)
      map('i', '<C-p>', go_parent)
      map('n', '<C-p>', go_parent)
      map('i', '<C-s>', go_children)
      map('n', '<C-s>', go_children)
      map('i', '<C-f>', go_browse)
      map('n', '<C-f>', go_browse)
      map('i', '<C-v>', function() do_split('right') end)
      map('n', '<C-v>', function() do_split('right') end)
      map('i', '<C-x>', function() do_split('left') end)
      map('n', '<C-x>', function() do_split('left') end)

      return true
    end,
  }):find()
end

--- Scrollable float picker. <CR> opens note/subview at cursor; / filters
--- in place (refreshes the same buffer, does not open a new window —
--- matches the tag-panel/trash-panel convention); q/<Esc> closes.
local function float_view_picker(name, paths, invocation_win, invocation_was_sidebar)
  local index       = require('pkm.index')
  local children    = get_view_children(name)
  local all_sorted  = sort_paths_by_type(paths)

  local buf, win
  local line_paths, line_subs = {}, {}
  local filter_query = nil

  local function render()
    local sorted, filtered_children = all_sorted, children
    if filter_query and filter_query ~= '' then
      local needle = filter_query:lower()
      local fc, fp = {}, {}
      for _, c in ipairs(children) do
        if c:lower():find(needle, 1, true) then fc[#fc + 1] = c end
      end
      for _, p in ipairs(all_sorted) do
        local e     = index.get(p)
        local title = (e and e.title or vim.fn.fnamemodify(p, ':t:r')):lower()
        if title:find(needle, 1, true) then fp[#fp + 1] = p end
      end
      filtered_children, sorted = fc, fp
    end

    local total         = #sorted + #filtered_children
    local filter_label   = (filter_query and filter_query ~= '')
      and ('  [filter: ' .. filter_query .. ']') or ''
    local header = string.format(
      '  View: %s  ·  %d note%s%s  ·  <CR> open  ·  / search  ·  <C-b> views  ·  <C-p> parent  ·  <C-s> subs  ·  <C-f> browse all  ·  <C-v>/<C-x> split  ·  q close',
      name, total, total == 1 and '' or 's', filter_label)
    local lines = { header, '  ' .. string.rep('─', math.max(#header - 2, 10)) }
    line_paths, line_subs = {}, {}

    for _, child in ipairs(filtered_children) do
      local c_count = #M.match_all(child)
      lines[#lines + 1] = string.format('  [v] %s  (%d notes)', child, c_count)
      line_subs[#lines] = child
    end
    if #filtered_children > 0 and #sorted > 0 then
      lines[#lines + 1] = '  ' .. string.rep('─', 52)
    end
    for _, p in ipairs(sorted) do
      local e         = index.get(p)
      local note_type = e and e.note_type or 'other'
      local title     = e and e.title or vim.fn.fnamemodify(p, ':t:r')
      lines[#lines + 1] = '  ' .. type_prefix(note_type) .. ' ' .. title
      line_paths[#lines] = p
    end
    if total == 0 then
      lines[#lines + 1] = (filter_query and filter_query ~= '')
        and '  (no matches)' or '  (empty)'
    end

    vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
    if #lines >= 3 and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, { 3, 2 })
    end
  end

  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })

  local width  = math.min(math.max(70, #name + 20), vim.o.columns - 4)
  local height = math.min(#all_sorted + #children + 6, math.floor(vim.o.lines * 0.7))
  win = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    width     = width,
    height    = height,
    col       = math.floor((vim.o.columns - width)  / 2),
    row       = math.floor((vim.o.lines   - height) / 2),
    style     = 'minimal',
    border    = 'rounded',
    title     = string.format(' PKMView: %s ', name),
    title_pos = 'center',
  })

  render()

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  local function open_at_cursor()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    if line_subs[row] then
      close()
      vim.schedule(function() M.open(line_subs[row]) end)
      return
    end
    if line_paths[row] then
      close()
      vim.cmd('edit ' .. vim.fn.fnameescape(line_paths[row]))
    end
  end

  local function go_back()
    close(); vim.schedule(function() M.open_views_panel() end)
  end

  local function go_parent()
    local parent = get_view_parent(name)
    if parent then
      close(); vim.schedule(function() M.open(parent) end)
    else
      vim.notify('[pkm] this view has no parent', vim.log.levels.INFO)
    end
  end

  local function go_children()
    local ch = get_view_children(name)
    if #ch == 0 then
      vim.notify('[pkm] this view has no subviews', vim.log.levels.INFO)
      return
    end
    close()
    vim.schedule(function()
      vim.ui.select(ch, {
        prompt      = string.format("Subviews of '%s':", name),
        format_item = function(n)
          return string.format('%s  (%d)', n, #M.match_all(n))
        end,
      }, function(sel) if sel then M.open(sel) end end)
    end)
  end

  local function do_search()
    vim.fn.inputsave()
    local query = vim.fn.input('Filter: ', filter_query or '')
    vim.fn.inputrestore()
    filter_query = (query and query ~= '') and query or nil
    render()
  end

  local ko = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set('n', '<CR>',  open_at_cursor, ko)
  vim.keymap.set('n', '/',     do_search,      ko)
  vim.keymap.set('n', '<C-b>', go_back,        ko)
  vim.keymap.set('n', '<C-p>', go_parent,      ko)
  vim.keymap.set('n', '<C-s>', go_children,    ko)
  vim.keymap.set('n', '<C-f>', function()
    close(); vim.schedule(function() M.open_views_panel('browse') end)
  end, ko)
  vim.keymap.set('n', '<C-v>', function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    if line_subs[row] then return end
    local p = line_paths[row]
    if not p then return end
    close()
    vim.schedule(function() open_relative_split('right', p, invocation_win, invocation_was_sidebar) end)
  end, ko)
  vim.keymap.set('n', '<C-x>', function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    if line_subs[row] then return end
    local p = line_paths[row]
    if not p then return end
    close()
    vim.schedule(function() open_relative_split('left', p, invocation_win, invocation_was_sidebar) end)
  end, ko)
  vim.keymap.set('n', 'q',     close,          ko)
  vim.keymap.set('n', '<Esc>', close,          ko)
end

--- Prompt the user to choose a view from all defined views.
local function pick_view()
  local names = M.list()
  if #names == 0 then
    vim.notify(
      'PKMView: no views defined. Use :PKMViewNew to create one.',
      vim.log.levels.WARN)
    return
  end
  vim.ui.select(names, {
    prompt      = 'Open view:',
    format_item = function(n) return n end,
  }, function(sel)
    if sel then M.open(sel) end
  end)
end

-- =============================================================================
-- SECTION: Public API — open
-- =============================================================================

--- Activate a named project view.
--- If name is nil or empty, presents a picker of all defined views.
---@param name string|nil
function M.open(name)
  if not name or name == '' then
    pick_view()
    return
  end

  local paths = M.match_all(name)

  if #paths == 0 then
    vim.notify(
      string.format("PKMView '%s': no notes matched the filter.", name),
      vim.log.levels.INFO)
    return
  end
  _last_view = name

  local invocation_win = vim.api.nvim_get_current_win()
  local invocation_was_sidebar =
    vim.bo[vim.api.nvim_win_get_buf(invocation_win)].filetype == 'pkm-sidebar'

  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    telescope_view_picker(name, paths, invocation_win, invocation_was_sidebar)
  else
    float_view_picker(name, paths, invocation_win, invocation_was_sidebar)
  end
end

--- Reopen the last view activated in this session.
--- Session-scoped: does not persist across Neovim restarts.
---@return nil
function M.open_last()
  if not _last_view then
    vim.notify('[pkm] no view has been activated yet this session', vim.log.levels.INFO)
    return
  end
  M.open(_last_view)
end

-- =============================================================================
-- SECTION: Views panel and view-deletion panel
-- =============================================================================
-- Replaces the former tree-picker M.list_views() (both go_back() callers
-- below now point here instead, so "browse all views" is one consistent
-- panel-based UI regardless of entry point, not two different UIs
-- depending on how you got there).
--
-- Deliberately two separate panels, not one with a delete key: the views
-- panel below has no way to delete a view at all — that's the whole point
-- of splitting it out, matching the trash-restore panel's own precedent of
-- keeping destructive actions out of a panel meant for casual browsing.

--- Telescope tree/browse picker, restored to give Telescope users live
--- search-as-you-type — the panel.lua fallback below (_views_panel) can
--- only ever do prompt-then-refilter, since it isn't backed by a Telescope
--- prompt buffer. mode='views' (default) shows the view hierarchy with
--- n/new and u/update bound in normal mode only (letter keys can't be
--- insert-mode-bound without eating literal typed characters in the
--- prompt — <Esc> out of the prompt first, matching how Telescope's own
--- normal-mode-only actions already work elsewhere). mode='browse' shows
--- all notes, unscoped, substring-filtered (never fuzzy, matching this
--- project's own search convention throughout).
---@param mode 'views'|'browse'|nil
local function telescope_views_tree_picker(mode, invocation_win, invocation_was_sidebar)
  mode = mode or 'views'
  local pickers      = require('telescope.pickers')
  local finders       = require('telescope.finders')
  local sorters       = require('telescope.sorters')
  local actions       = require('telescope.actions')
  local action_state  = require('telescope.actions.state')
  local previewers    = require('telescope.previewers')

  if mode == 'browse' then
    local index   = require('pkm.index')
    local entries = index.get_all()
    table.sort(entries, function(a, b)
      local ta = _TYPE_ORDER[a.note_type] or 6
      local tb = _TYPE_ORDER[b.note_type] or 6
      if ta ~= tb then return ta < tb end
      return (a.title or a.filename or ''):lower() < (b.title or b.filename or ''):lower()
    end)
    local items = {}
    for _, e in ipairs(entries) do
      items[#items + 1] = {
        value   = e.path,
        display = type_prefix(e.note_type) .. ' ' .. (e.title or e.filename or '?'),
        ordinal = e.title or e.filename or e.path,
      }
    end

    pickers.new({
      sorting_strategy = 'ascending',
      layout_config    = { prompt_position = 'top' },
    }, {
      prompt_title = string.format('Browse All Notes  (%d)  <C-f> views  <C-v>/<C-x> split', #items),
      finder = finders.new_dynamic({
        fn = function(prompt)
          if not prompt or prompt == '' then return items end
          local needle = prompt:lower()
          local out = {}
          for _, item in ipairs(items) do
            if item.display:lower():find(needle, 1, true) then out[#out + 1] = item end
          end
          return out
        end,
        entry_maker = function(item) return item end,
      }),
      sorter    = sorters.empty(),
      previewer = previewers.vim_buffer_cat.new({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local sel = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if sel then vim.cmd('edit ' .. vim.fn.fnameescape(sel.value)) end
        end)
        local function go_views()
          actions.close(prompt_bufnr)
          vim.schedule(function() M.open_views_panel('views') end)
        end
        local function do_split(direction)
          local sel = action_state.get_selected_entry()
          if not sel then return end
          actions.close(prompt_bufnr)
          vim.schedule(function()
            open_relative_split(direction, sel.value, invocation_win, invocation_was_sidebar)
          end)
        end
        map('i', '<C-f>', go_views)
        map('n', '<C-f>', go_views)
        map('i', '<C-v>', function() do_split('right') end)
        map('n', '<C-v>', function() do_split('right') end)
        map('i', '<C-x>', function() do_split('left') end)
        map('n', '<C-x>', function() do_split('left') end)
        return true
      end,
    }):find()
    return
  end

  local tree  = build_tree_entries()
  local items = {}
  for _, e in ipairs(tree) do
    local count  = #M.match_all(e.name)
    local indent = string.rep('  ', e.depth)
    local marker = e.has_children and '▶ ' or '• '
    items[#items + 1] = {
      name    = e.name,
      display = string.format('%s%s%s  (%d)', indent, marker, e.name, count),
    }
  end

  pickers.new({
    sorting_strategy = 'ascending',
    layout_config    = { prompt_position = 'top' },
  }, {
    prompt_title = 'PKM Views  ·  <C-f> browse all  ·  n new  ·  u update',
    finder = finders.new_dynamic({
      fn = function(prompt)
        if not prompt or prompt == '' then return items end
        local needle = prompt:lower()
        local out = {}
        for _, item in ipairs(items) do
          if item.name:lower():find(needle, 1, true) then out[#out + 1] = item end
        end
        return out
      end,
      entry_maker = function(item)
        return { value = item.name, display = item.display, ordinal = item.name }
      end,
    }),
    sorter = sorters.empty(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local sel = action_state.get_selected_entry()
        if sel then M.open(sel.value) end
      end)

      local function go_browse()
        actions.close(prompt_bufnr)
        vim.schedule(function() M.open_views_panel('browse') end)
      end
      local function do_new()
        actions.close(prompt_bufnr)
        vim.schedule(function() vim.cmd('PKMViewNew') end)
      end
      local function do_update()
        local sel = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then vim.schedule(function() M.edit_view(sel.value) end) end
      end

      map('i', '<C-f>', go_browse)
      map('n', '<C-f>', go_browse)
      map('n', 'n', do_new)
      map('n', 'u', do_update)

      return true
    end,
  }):find()
end

local _views_panel = panel.create({
  name          = 'viewspanel',
  split_cmd     = 'noautocmd botright split',
  focus_on_open = true,
  resize = function(state, lines)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_height(state.win, math.min(#lines + 1, 16))
    end
  end,
  -- 'views' (default) shows the view tree; 'browse' shows all notes,
  -- unscoped, toggled in place with <C-f> — same window and buffer, no
  -- closing one popup and opening another. Only reached when Telescope
  -- isn't installed (see telescope_views_tree_picker above for that path).
  -- Browse mode here is a light substring-only convenience, NOT a
  -- replacement for :PKMBrowse's own full tag:/title:/text: field-prefix
  -- grammar — that command keeps its own richer implementation; this is
  -- just a quick peek reachable without leaving the views panel.
  build_lines = function(state)
    state.mode = state.mode or 'views'

    if state.mode == 'browse' then
      local index    = require('pkm.index')
      local entries  = index.get_all()
      local filtered = entries
      if state.filter and state.filter ~= '' then
        local needle = state.filter:lower()
        local f = {}
        for _, e in ipairs(entries) do
          local title = (e.title or ''):lower()
          local fname = (e.filename or ''):lower()
          local tags  = table.concat(e.tags or {}, ' '):lower()
          if title:find(needle, 1, true)
          or fname:find(needle, 1, true)
          or tags:find(needle, 1, true) then
            f[#f + 1] = e
          end
        end
        filtered = f
      end
      table.sort(filtered, function(a, b)
        local ta = _TYPE_ORDER[a.note_type] or 6
        local tb = _TYPE_ORDER[b.note_type] or 6
        if ta ~= tb then return ta < tb end
        return (a.title or a.filename or ''):lower() < (b.title or b.filename or ''):lower()
      end)

      local filter_label = (state.filter and state.filter ~= '')
        and ('  [filter: ' .. state.filter .. ']') or ''
      local lines = {
        string.format('  Browse All  (%d)%s  <CR> open  <C-f> views  <C-v>/<C-x> split  / search  q close',
          #filtered, filter_label),
      }
      local map = {}
      for _, e in ipairs(filtered) do
        lines[#lines + 1] = string.format('  %s %s',
          type_prefix(e.note_type), e.title or e.filename or '?')
        map[#lines] = e.path
      end
      if #filtered == 0 then
        lines[#lines + 1] = '  (no notes match)'
      end
      return lines, map
    end

    local tree = build_tree_entries()
    local filtered = tree
    if state.filter and state.filter ~= '' then
      local needle = state.filter:lower()
      local f = {}
      for _, e in ipairs(tree) do
        if e.name:lower():find(needle, 1, true) then f[#f + 1] = e end
      end
      filtered = f
    end

    local filter_label = (state.filter and state.filter ~= '')
      and ('  [filter: ' .. state.filter .. ']') or ''
    local lines = {
      string.format('  Views  (%d)%s  <CR> open  n new  u update  <C-f> browse all  / search  q close',
        #filtered, filter_label),
    }
    local map = {}
    for _, e in ipairs(filtered) do
      local count  = #M.match_all(e.name)
      local indent = string.rep('  ', e.depth)
      local marker = e.has_children and '▶ ' or '• '
      lines[#lines + 1] = string.format('  %s%s%s  (%d)', indent, marker, e.name, count)
      map[#lines] = e.name
    end
    if #filtered == 0 then
      lines[#lines + 1] = (state.filter and state.filter ~= '')
        and '  (no views match)' or '  (no views defined — press n to create one)'
    end
    return lines, map
  end,
  -- Deliberately no delete key — see M.open_view_deletion_panel() below.
  keymaps = {
    ['<CR>'] = function(state, helpers)
      local target = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not target then return end
      helpers.close()
      if state.mode == 'browse' then
        vim.schedule(function() vim.cmd('edit ' .. vim.fn.fnameescape(target)) end)
      else
        vim.schedule(function() M.open(target) end)
      end
    end,
    ['<C-f>'] = function(state, helpers)
      state.mode   = (state.mode == 'browse') and 'views' or 'browse'
      state.filter = nil
      helpers.refresh()
    end,
    ['<C-v>'] = function(state, helpers)
      if state.mode ~= 'browse' then return end
      local target = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not target then return end
      helpers.close()
      vim.schedule(function()
        open_relative_split('right', target, state.invocation_win, state.invocation_was_sidebar)
      end)
    end,
    ['<C-x>'] = function(state, helpers)
      if state.mode ~= 'browse' then return end
      local target = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not target then return end
      helpers.close()
      vim.schedule(function()
        open_relative_split('left', target, state.invocation_win, state.invocation_was_sidebar)
      end)
    end,
    ['n'] = function(state, helpers)
      if state.mode == 'browse' then return end
      helpers.close()
      vim.schedule(function() vim.cmd('PKMViewNew') end)
    end,
    ['u'] = function(state, helpers)
      if state.mode == 'browse' then return end
      local name = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not name then return end
      helpers.close()
      vim.schedule(function() M.edit_view(name) end)
    end,
    ['/'] = function(state, helpers)
      vim.fn.inputsave()
      local query = vim.fn.input('Filter: ', state.filter or '')
      vim.fn.inputrestore()
      state.filter = (query and query ~= '') and query or nil
      helpers.refresh()
    end,
  },
})

--- Open the views panel: browse the view tree, open a view (<CR>), create
--- one (n), or edit/rename/reparent one (u). Dispatches to Telescope when
--- available (telescope_views_tree_picker — live search) and to the
--- panel.lua fallback otherwise (_views_panel), matching M.open()'s own
--- has_telescope convention. <C-f> switches to a lightweight all-notes
--- browse mode and back on either backend — no closing this panel to open
--- a separate one. No deletion key by design — see
--- M.open_view_deletion_panel().
---@param mode 'views'|'browse'|nil  Initial mode; defaults to 'views'.
---@return nil
function M.open_views_panel(mode)
  local invocation_win = vim.api.nvim_get_current_win()
  local invocation_was_sidebar =
    vim.bo[vim.api.nvim_win_get_buf(invocation_win)].filetype == 'pkm-sidebar'

  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    telescope_views_tree_picker(mode, invocation_win, invocation_was_sidebar)
  else
    _views_panel.open({
      filter = '', mode = mode or 'views',
      invocation_win = invocation_win, invocation_was_sidebar = invocation_was_sidebar,
    })
  end
end

local _delete_panel = panel.create({
  name          = 'viewdeletepanel',
  split_cmd     = 'noautocmd botright split',
  focus_on_open = true,
  resize = function(state, lines)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_height(state.win, math.min(#lines + 1, 16))
    end
  end,
  build_lines = function(state)
    local tree = build_tree_entries()
    local filtered = tree
    if state.filter and state.filter ~= '' then
      local needle = state.filter:lower()
      local f = {}
      for _, e in ipairs(tree) do
        if e.name:lower():find(needle, 1, true) then f[#f + 1] = e end
      end
      filtered = f
    end

    local filter_label = (state.filter and state.filter ~= '')
      and ('  [filter: ' .. state.filter .. ']') or ''
    local lines = {
      string.format('  Delete View  (%d)%s  <CR> select (confirms)  / search  q close',
        #filtered, filter_label),
    }
    local map = {}
    for _, e in ipairs(filtered) do
      local count  = #M.match_all(e.name)
      local indent = string.rep('  ', e.depth)
      local marker = e.has_children and '▶ ' or '• '
      lines[#lines + 1] = string.format('  %s%s%s  (%d)', indent, marker, e.name, count)
      map[#lines] = e.name
    end
    if #filtered == 0 then
      lines[#lines + 1] = (state.filter and state.filter ~= '')
        and '  (no views match)' or '  (no views defined)'
    end
    return lines, map
  end,
  keymaps = {
    ['<CR>'] = function(state, helpers)
      local name = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not name then return end
      -- Warn about orphaned children: M.delete() only removes this
      -- entry, it does not touch any subproject whose parent field
      -- pointed here (a pre-existing, out-of-scope-for-this-phase
      -- limitation) — surfacing it in the confirm prompt at least makes
      -- the consequence visible before it happens, not only after.
      local children = get_view_children(name)
      local msg = string.format("Delete view '%s'?", name)
      if #children > 0 then
        msg = msg .. string.format(
          '\n(%d subview%s reference this as parent and will be orphaned)',
          #children, #children == 1 and '' or 's')
      end
      local choice = vim.fn.confirm(msg, '&Yes\n&No', 2)
      if choice == 1 then
        M.delete(name)
        helpers.refresh()
      end
    end,
    ['/'] = function(state, helpers)
      vim.fn.inputsave()
      local query = vim.fn.input('Filter: ', state.filter or '')
      vim.fn.inputrestore()
      state.filter = (query and query ~= '') and query or nil
      helpers.refresh()
    end,
  },
})

--- Open the view-deletion panel: browse → select → confirm before delete
--- (vim.fn.confirm, single keypress — matches the existing convention used
--- by the buffer panel's own "close with unsaved changes" prompt, not a
--- typed "yes"/"no" like :PKMEmptyTrash's heavier confirmation, since
--- deleting a view only removes a saved filter, never any note content).
---@return nil
function M.open_view_deletion_panel()
  _delete_panel.open({ filter = '' })
end

-- =============================================================================
-- SECTION: Edit UI
-- =============================================================================

--- Open a floating edit UI for a named view.
--- Header shows name and (for subprojects) the parent, read-only for reference.
--- The expression line is pre-filled with the current filter.
--- <CR> validates and saves. <C-r> resets to the original. <Esc> cancels.
--- On validation failure the float stays open in insert mode for correction.
---@param name string
local function edit_view_float(name)
  local projects = get_projects()
  local expr     = projects[name]
  if not expr then
    vim.notify(string.format("PKMView: no view named '%s'", name),
      vim.log.levels.WARN)
    return
  end

  local is_sub          = type(expr) == 'table'
  local original_filter = is_sub and expr.filter or expr
  local parent_name     = is_sub and expr.parent or nil

  local header = { '  View: ' .. name }
  if is_sub then
    header[#header + 1] = '  Parent: ' .. parent_name
  end
  header[#header + 1] = '  ' .. string.rep('─', 50)

  local expr_line_idx = #header + 1

  local all_lines = {}
  for _, l in ipairs(header) do all_lines[#all_lines + 1] = l end
  all_lines[#all_lines + 1] = original_filter
  all_lines[#all_lines + 1] = ''
  all_lines[#all_lines + 1] = '  <CR> save   <C-r> reset   <Esc> cancel'

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, all_lines)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })

  local width = math.min(
    math.max(60, #original_filter + 8),
    vim.o.columns - 4)
  local height = #all_lines + 2

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    width     = width,
    height    = height,
    col       = math.floor((vim.o.columns - width)  / 2),
    row       = math.floor((vim.o.lines   - height) / 2),
    style     = 'minimal',
    border    = 'rounded',
    title     = is_sub and ' Edit Subproject ' or ' Edit View ',
    title_pos = 'center',
  })

  vim.api.nvim_win_set_cursor(win, { expr_line_idx, #original_filter })
  vim.cmd('startinsert!')

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function do_save()
    vim.cmd('stopinsert')
    local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local new_expr  = (buf_lines[expr_line_idx] or ''):match('^%s*(.-)%s*$')

    if new_expr == '' then
      vim.notify('[pkm] filter expression cannot be empty', vim.log.levels.WARN)
      vim.cmd('startinsert!')
      return
    end

    local _, parse_err = require('pkm.filter').parse(new_expr)
    if parse_err then
      vim.notify('[pkm] invalid filter: ' .. parse_err, vim.log.levels.ERROR)
      vim.cmd('startinsert!')
      return
    end

    close()
    vim.schedule(function()
      if is_sub then
        M.save_subproject(name, parent_name, new_expr)
      else
        M.save(name, new_expr)
      end
    end)
  end

  local function do_reset()
    vim.api.nvim_buf_set_lines(buf, expr_line_idx - 1, expr_line_idx,
      false, { original_filter })
    vim.api.nvim_win_set_cursor(win, { expr_line_idx, #original_filter })
    vim.cmd('startinsert!')
    vim.notify('[pkm] expression reset to original', vim.log.levels.INFO)
  end

  local ko = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set({ 'n', 'i' }, '<CR>',  do_save,  ko)
  vim.keymap.set({ 'n', 'i' }, '<C-r>', do_reset, ko)
  vim.keymap.set({ 'n', 'i' }, '<Esc>', function()
    vim.cmd('stopinsert')
    close()
  end, ko)
end

--- Prompt for a new name and rename a view in views.json.
--- Also updates any child subproject entries whose parent field matches the
--- old name. Config-only views (not present in views.json) cannot be renamed
--- this way; the user receives an explanatory message.
---@param old_name string
local function rename_view_prompt(old_name)
  local data = load_sidecar()
  if not data[old_name] then
    if (get_config().projects or {})[old_name] then
      vim.notify(
        string.format(
          "[pkm] '%s' is defined in your Neovim config — edit it there to rename",
          old_name),
        vim.log.levels.WARN)
    else
      vim.notify(string.format("[pkm] '%s' is not in views.json", old_name),
        vim.log.levels.WARN)
    end
    return
  end

  vim.fn.inputsave()
  local new_name = vim.fn.input('Rename view to: ', old_name)
  vim.fn.inputrestore()

  if not new_name or new_name:match('^%s*$') then
    vim.notify('[pkm] rename cancelled', vim.log.levels.INFO)
    return
  end
  new_name = new_name:match('^%s*(.-)%s*$')

  if new_name == old_name then
    vim.notify('[pkm] name unchanged', vim.log.levels.INFO)
    return
  end

  -- Block if new_name already exists in the merged set (config OR sidecar).
  if get_projects()[new_name] then
    vim.notify(
      string.format("[pkm] a view named '%s' already exists", new_name),
      vim.log.levels.ERROR)
    return
  end

  -- Move the sidecar entry and propagate to child subprojects.
  data[new_name] = data[old_name]
  data[old_name] = nil
  for k, v in pairs(data) do
    if type(v) == 'table' and v.parent == old_name then
      data[k] = { parent = new_name, filter = v.filter }
    end
  end

  if save_sidecar(data) then
    -- Keep session state consistent.
    if _last_view == old_name then _last_view = new_name end
    local ct = get_tab()
    if ct.name == old_name then ct.name = new_name end
    vim.notify(
      string.format("[pkm] view renamed: '%s' → '%s'", old_name, new_name),
      vim.log.levels.INFO)

    -- config.lua subprojects cannot be safely rewritten by the plugin;
    -- warn (never block — the sidecar rename above already succeeded).
    local stale = {}
    for k, v in pairs(get_config().projects or {}) do
      if type(v) == 'table' and v.parent == old_name then
        stale[#stale + 1] = k
      end
    end
    if #stale > 0 then
      table.sort(stale)
      vim.notify(
        string.format(
          "[pkm] config.lua subproject(s) still reference the old name '%s': %s — update their 'parent' field by hand",
          old_name, table.concat(stale, ', ')),
        vim.log.levels.WARN)
    end

    M.refresh_sidebar_if_open()
  end
end

--- Prompt for a new parent and reparent a subproject view.
--- Validates that the chosen parent is not the view itself or any of its
--- descendants (which would create a cycle). Config-only subprojects cannot
--- be reparented via this mechanism.
---@param name string  Name of the subproject view to reparent
local function reparent_view_prompt(name)
  local projects = get_projects()
  local expr     = projects[name]
  if type(expr) ~= 'table' then
    vim.notify(
      string.format("[pkm] '%s' is not a subproject (has no parent field)", name),
      vim.log.levels.WARN)
    return
  end
  local current_parent = expr.parent

  -- All views except the view itself are candidate parents; cycle check below.
  local candidates = {}
  for k in pairs(projects) do
    if k ~= name then candidates[#candidates + 1] = k end
  end
  -- Views with more existing subviews sort first — they're the most likely
  -- home for a new one. Ties (including the common zero-subviews case)
  -- fall back to the same case-insensitive order used everywhere else.
  table.sort(candidates, function(a, b)
    local ca, cb = #get_view_children(a), #get_view_children(b)
    if ca ~= cb then return ca > cb end
    return a:lower() < b:lower()
  end)

  if #candidates == 0 then
    vim.notify('[pkm] no other views available as parent', vim.log.levels.WARN)
    return
  end

  vim.ui.select(candidates, {
    prompt      = string.format(
      "New parent for '%s'  (current: '%s'):", name, current_parent),
    format_item = function(n) return n end,
  }, function(new_parent)
    if not new_parent then
      vim.notify('[pkm] reparent cancelled', vim.log.levels.INFO)
      return
    end
    if new_parent == current_parent then
      vim.notify('[pkm] parent unchanged', vim.log.levels.INFO)
      return
    end

    -- Cycle guard: walk descendants of `name` to confirm `new_parent`
    -- does not appear in the subtree rooted at `name`.
    local function is_descendant(ancestor, target)
      for _, child in ipairs(get_view_children(ancestor)) do
        if child == target or is_descendant(child, target) then return true end
      end
      return false
    end

    if is_descendant(name, new_parent) then
      vim.notify(
        string.format(
          "[pkm] cannot reparent '%s' under '%s' — would create a hierarchy cycle",
          name, new_parent),
        vim.log.levels.ERROR)
      return
    end

    local data = load_sidecar()
    if not data[name] then
      vim.notify(
        string.format(
          "[pkm] '%s' is only in Neovim config — edit it there to change the parent",
          name),
        vim.log.levels.WARN)
      return
    end

    data[name] = { parent = new_parent, filter = expr.filter }
    if save_sidecar(data) then
      vim.notify(
        string.format("[pkm] '%s' reparented: '%s' → '%s'",
          name, current_parent, new_parent),
        vim.log.levels.INFO)
      M.refresh_sidebar_if_open()
    end
  end)
end

--- Open an edit UI for a named view.
--- Presents an action picker: "Edit filter expression" is always available;
--- "Rename" and "Change parent" (subprojects only) are offered when the view
--- is stored in views.json (not config-only).
--- If name is nil, a picker of all defined views opens first.
---@param name string|nil
function M.edit_view(name)
  if not name or name == '' then
    local names = M.list()
    if #names == 0 then
      vim.notify('[pkm] no views defined', vim.log.levels.WARN)
      return
    end
    vim.ui.select(names, {
      prompt      = 'Edit view:',
      format_item = function(n) return n end,
    }, function(sel)
      if sel then M.edit_view(sel) end
    end)
    return
  end

  local projects = get_projects()
  if not projects[name] then
    vim.notify(string.format("[pkm] no view named '%s'", name), vim.log.levels.WARN)
    return
  end

  local is_sub     = type(projects[name]) == 'table'
  local in_sidecar = load_sidecar()[name] ~= nil

  local options = { 'Edit filter expression' }
  if in_sidecar then
    options[#options + 1] = 'Rename'
    if is_sub then
      options[#options + 1] = 'Change parent'
    end
  end

  vim.ui.select(options, {
    prompt      = string.format(
      "PKMViewUpdate — '%s'  (%s):",
      name,
      is_sub and 'subproject' or 'simple view'),
    format_item = function(o) return o end,
  }, function(choice)
    if not choice then return end
    if choice == 'Edit filter expression' then
      edit_view_float(name)
    elseif choice == 'Rename' then
      rename_view_prompt(name)
    elseif choice == 'Change parent' then
      reparent_view_prompt(name)
    end
  end)
end

-- =============================================================================
-- SECTION: Sidebar
-- =============================================================================

--- Build overview display lines listing all views in the hierarchy.
---@return string[], table  lines, view_lines (1-based line number → view name)
local function sidebar_build_overview()
  local tree       = build_tree_entries()
  local lines = {
    '  PKM Views',
    '  ' .. string.rep('─', 38),
    ''
  }
  local view_lines = {}

  for _, e in ipairs(tree) do
    local count  = #M.match_all(e.name)
    local indent = string.rep('  ', e.depth + 1)
    local marker = e.has_children and '▶ ' or '• '
    lines[#lines + 1] = string.format('%s%s%s  (%d)', indent, marker, e.name, count)
    view_lines[#lines] = e.name
  end

  if #tree == 0 then
    lines[#lines + 1] = '  (no views defined — use :PKMViewNew)'
  end

  return lines, view_lines
end

--- Build detail display lines for a specific view.
---@param name  string
---@param paths string[]
---@return string[], table, integer, string[]
local function sidebar_build_lines(name, paths, total_count)
  local index    = require('pkm.index')
  local parent   = get_view_parent(name)
  local children = get_view_children(name)
  local lines    = {}
  local tree_entries = {}

  if parent or #children > 0 then
    if parent then
      local p_count = #M.match_all(parent)
      lines[#lines + 1] = string.format('  ▶ %s  (%d)', parent, p_count)
      tree_entries[#lines] = { name = parent, is_current = false }
    end


    lines[#lines + 1] = string.format('  ▼ %s  (%d)', name, #paths)
    tree_entries[#lines] = { name = name, is_current = true }

    for _, child in ipairs(children) do
      local c_count = #M.match_all(child)
      lines[#lines + 1] = string.format('  ▶ %s  (%d)', child, c_count)
      tree_entries[#lines] = { name = child, is_current = false }
    end

    lines[#lines + 1] = '  ' .. string.rep('─', 38)
    lines[#lines + 1] = ''

  else
    local count = #paths
    local count_label
    if total_count and total_count ~= count then
      count_label = string.format('%d of %d', count, total_count)
    else
      count_label = tostring(count)
    end
    lines[#lines + 1] = '  PKMView: ' .. name
      .. '  (' .. count_label .. ' note' .. (count == 1 and '' or 's') .. ')'
    lines[#lines + 1] = '  ' .. string.rep('─', 38)
    lines[#lines + 1] = ''
  end

  local header_count = #lines
  local sorted       = sort_paths_by_mtime(paths)

  local dm = require('pkm.ui').get_display_mode()
  for _, path in ipairs(sorted) do
    local entry     = index.get(path)
    local note_type = entry and entry.note_type or 'other'
    local label
    if entry then
      if dm == 'title' and entry.title and entry.title ~= '' then
        label = entry.title
      else
        label = strip_display_prefix(entry.filename, note_type)
      end
    else
      label = vim.fn.fnamemodify(path, ':t:r')
    end
    lines[#lines + 1] = string.format('  %s %s', type_prefix(note_type), label)
  end

  if #sorted == 0 then
    lines[#lines + 1] = '  (no notes match)'
  end

  return lines, tree_entries, header_count, sorted
end

--- Write lines to the sidebar buffer.
local function sidebar_set_content(lines)
  local t = get_tab()
  vim.api.nvim_set_option_value('modifiable', true,  { buf = t.buf })
  vim.api.nvim_buf_set_lines(t.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = t.buf })
end

--- Switch the open sidebar to overview mode.
local function sidebar_switch_to_overview()
  local t = get_tab()
  t.type_filter = nil
  local lines, view_lines = sidebar_build_overview()
  t.mode         = 'overview'
  t.name         = nil
  t.paths        = {}
  t.tree         = {}
  t.header_count = 0
  t.view_lines   = view_lines
  sidebar_set_content(lines)
  if vim.api.nvim_win_is_valid(t.win) then
    vim.api.nvim_win_set_cursor(
      t.win, { math.min(4, vim.api.nvim_buf_line_count(t.buf)), 0 })
  end
end

--- Switch the open sidebar to detail mode for a named view.
---@param name string
local function sidebar_switch_to_detail(name)
  local t = get_tab()
  local all_paths = M.match_all(name)

  local display_paths = all_paths
  if t.type_filter then
    local idx_m = require('pkm.index')
    local filtered = {}
    for _, p in ipairs(all_paths) do
      local e = idx_m.get(p)
      if e and e.note_type == t.type_filter then filtered[#filtered + 1] = p end
    end
    display_paths = filtered
  end

  local lines, tree_entries, header_count, sorted =
    sidebar_build_lines(name, display_paths, #all_paths)
  t.mode         = 'detail'
  t.name         = name
  t.paths        = sorted
  t.tree         = tree_entries
  t.header_count = header_count
  t.view_lines   = {}
  sidebar_set_content(lines)
  if vim.api.nvim_win_is_valid(t.win) and #sorted > 0 then
    vim.api.nvim_win_set_cursor(t.win, { header_count + 1, 0 })
  end
end

--- Open a compact help float listing all sidebar keymaps.
local function sidebar_show_help()
  local lines = {
    '  <CR>     open note / enter view',
    '  N<CR>    open note in window N (leftmost = 1)',
    '  <C-v>    open note in new vertical split',
    '  <C-t>    cycle type filter  (all/n/a/b/j/s)',
    '  T        toggle filename / title labels',
    '  b        back (pop history)',
    '  <BS>     same as b',
    '  <C-b>    jump to overview',
  }
  if _panel_keymap_lhs then
    lines[#lines + 1] = string.format('  %-9s open views panel', _panel_keymap_lhs)
  end
  vim.list_extend(lines, {
    '  /        search (opens in main window)',
    '  r        refresh',
    '  q        close sidebar',
    '  ?        this help',
  })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_set_option_value('bufhidden',  'wipe', { buf = buf })

  local width  = 50
  local height = #lines + 2
  local win    = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    width     = width,
    height    = height,
    col       = math.floor((vim.o.columns - width) / 2),
    row       = math.floor((vim.o.lines   - height) / 2),
    style     = 'minimal',
    border    = 'rounded',
    title     = ' Sidebar Keymaps ',
    title_pos = 'center',
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  local ko = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set('n', 'q',     close, ko)
  vim.keymap.set('n', '<Esc>', close, ko)
  vim.keymap.set('n', '?',     close, ko)
end

--- Open or toggle the persistent view sidebar.
--- No name → close if open; open in overview mode if closed.
--- Named view → open detail; same name again while in detail → close.
--- Overview keymaps: <CR> enter view  <BS>/<C-b> notify  r refresh  q/<Esc> close
--- Detail keymaps:   <CR> open note or navigate  <BS> pop history or overview
---                   <C-b> jump to overview  / scoped search  r refresh  q/<Esc> close
---@param name string|nil
---@return nil
function M.open_sidebar(name)
  local t = get_tab()
  local my_tab_id = vim.api.nvim_get_current_tabpage()

  -- Clear stale state if the window was destroyed externally.
  if t.win and not vim.api.nvim_win_is_valid(t.win) then
    _tabs[my_tab_id] = nil
    t = get_tab()
  end

  if not name or name == '' then
    if t.win then
      vim.api.nvim_win_close(t.win, true)
      return
    end
  else
    if t.win then
      if t.mode == 'detail' and t.name == name then
        vim.api.nvim_win_close(t.win, true)
        return
      end
      sidebar_push_history()
      sidebar_switch_to_detail(name)
      return
    end
  end

  -- Open new sidebar window.
  local width    = (require('pkm').config.sidebar_width or 40)

  vim.cmd('noautocmd topleft vsplit')
  t.win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  t.buf = buf
  vim.api.nvim_win_set_buf(t.win, buf)
  vim.api.nvim_win_set_width(t.win, width)

  for opt, val in pairs({
    winfixbuf = true, winfixwidth = true, wrap = false,
    number = false, cursorline = true, signcolumn = 'no',
  }) do
    vim.api.nvim_set_option_value(opt, val, { win = t.win })
  end
  -- winfixwidth is now set; equalize other windows so the sidebar does not
  -- squeeze the leftmost editing window below a usable width.
  vim.cmd('wincmd =')

  for opt, val in pairs({
    bufhidden = 'wipe', buftype = 'nofile', swapfile = false,
  }) do
    vim.api.nvim_set_option_value(opt, val, { buf = buf })
  end

  vim.api.nvim_set_option_value('filetype', 'pkm-sidebar', { buf = buf })

  local function refresh_sidebar_sl()
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(t.win) then
        vim.api.nvim_set_option_value(
          'statusline',
          '  PKM Views  · CR open  · / search  · ? help  · q close',
          { win = t.win })
      end
    end)
  end
  refresh_sidebar_sl()
  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter' }, {
    buffer   = buf,
    callback = refresh_sidebar_sl,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer   = buf,
    once     = true,
    callback = function() _tabs[my_tab_id] = nil end,
  })

  local ko = { noremap = true, silent = true, buffer = buf }

  -- <CR>: mode-aware action
  vim.keymap.set('n', '<CR>', function()
    local ct  = get_tab()
    local row = vim.api.nvim_win_get_cursor(ct.win)[1]

    if ct.mode == 'overview' then
      local vname = ct.view_lines[row]
      if vname then
        sidebar_push_history()
        sidebar_switch_to_detail(vname)
      end
      return
    end

    -- detail: tree header line → navigate to that view
    local te = ct.tree[row]
    if te then
      if not te.is_current then
        sidebar_push_history()
        sidebar_switch_to_detail(te.name)
      end
      return
    end

    -- detail: note line → open in main window
    local idx = row - ct.header_count
    if idx < 1 or idx > #ct.paths then return end
    local path = ct.paths[idx]

    if vim.fn.filereadable(path) == 0 then
      vim.notify(
        '[pkm] file no longer exists: ' .. vim.fn.fnamemodify(path, ':t'),
        vim.log.levels.WARN)
      return
    end

    local _PANELS = { ['pkm-sidebar'] = true, ['pkm-bufpanel'] = true, ['netrw'] = true }

    -- [count]<CR>: open in the Nth editing window (1 = leftmost), sorted left→right.
    local count = vim.v.count
    if count > 0 then
      local candidates = {}
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= ct.win
        and vim.api.nvim_win_get_config(win).relative == '' then
          if not _PANELS[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
            candidates[#candidates + 1] = { win = win, col = vim.api.nvim_win_get_position(win)[2] }
          end
        end
      end
      local editing_wins = sort_wins_by_col(candidates)
      local slot = resolve_window_slot(count, #editing_wins)
      if slot then
        vim.api.nvim_set_current_win(editing_wins[slot].win)
        vim.cmd('edit ' .. vim.fn.fnameescape(path))
      else
        vim.notify(string.format('[pkm] no window %d (only %d editing window%s)',
          count, #editing_wins, #editing_wins == 1 and '' or 's'),
          vim.log.levels.WARN)
      end
      return
    end

    -- Default: prefer alternate window, fall back to first non-panel window.
    local target
    local alt_id = vim.fn.win_getid(vim.fn.winnr('#'))
    if alt_id ~= 0 and alt_id ~= ct.win
    and vim.api.nvim_win_is_valid(alt_id)
    and vim.api.nvim_win_get_config(alt_id).relative == '' then
      if not _PANELS[vim.bo[vim.api.nvim_win_get_buf(alt_id)].filetype] then
        target = alt_id
      end
    end
    if not target then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= ct.win
        and vim.api.nvim_win_get_config(win).relative == '' then
          if not _PANELS[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
            target = win; break
          end
        end
      end
    end
    if target then
      vim.api.nvim_set_current_win(target)
      vim.cmd('edit ' .. vim.fn.fnameescape(path))
    else
      vim.cmd('rightbelow vsplit ' .. vim.fn.fnameescape(path))
    end
  end, ko)

  -- <BS>: pop history; fall back to overview from detail, notify from overview
  vim.keymap.set('n', '<BS>', function()
    local state = sidebar_pop_history()
    if state then
      if state.mode == 'overview' then
        sidebar_switch_to_overview()
      else
        sidebar_switch_to_detail(state.name)
      end
    elseif get_tab().mode == 'overview' then
      vim.notify('[pkm] already at views overview', vim.log.levels.INFO)
    else
      sidebar_switch_to_overview()
    end
  end, ko)

  -- <C-b>: jump directly to overview, push current to history
  vim.keymap.set('n', '<C-b>', function()
    if get_tab().mode ~= 'overview' then
      sidebar_push_history()
      sidebar_switch_to_overview()
    end
  end, ko)

  if _panel_keymap_lhs then
    vim.keymap.set('n', _panel_keymap_lhs, function()
      M.open_views_panel()
    end, ko)
  end

  -- b: reliable alternative to <BS> on all terminals
  vim.keymap.set('n', 'b', function()
    local state = sidebar_pop_history()
    if state then
      if state.mode == 'overview' then
        sidebar_switch_to_overview()
      else
        sidebar_switch_to_detail(state.name)
      end
    elseif get_tab().mode == 'overview' then
      vim.notify('[pkm] already at views overview', vim.log.levels.INFO)
    else
      sidebar_switch_to_overview()
    end
  end, ko)

  -- /: scoped search — focus main window first so picker opens files there
  vim.keymap.set('n', '/', function()
    local ct = get_tab()
    local target
    local alt_id = vim.fn.win_getid(vim.fn.winnr('#'))
    if alt_id ~= 0 and alt_id ~= ct.win
    and vim.api.nvim_win_is_valid(alt_id)
    and vim.api.nvim_win_get_config(alt_id).relative == '' then
      target = alt_id
    end
    if not target then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= ct.win
        and vim.api.nvim_win_get_config(win).relative == '' then
          target = win; break
        end
      end
    end
    if target then vim.api.nvim_set_current_win(target) end
    local has_tele = pcall(require, 'telescope')
    if ct.mode == 'detail' then
      local title = string.format('Search: %s', ct.name)
      if has_tele then
        require('pkm.telescope').browse_paths(title, ct.paths)
      else
        require('pkm.ui').browse_paths(title, ct.paths)
      end
    else
      if has_tele then require('pkm.telescope').browse()
      else             require('pkm.ui').browse() end
    end
  end, ko)

  -- <C-v>: open note in a new vertical split (detail mode only)
  vim.keymap.set('n', '<C-v>', function()
    local ct  = get_tab()
    if ct.mode ~= 'detail' then return end
    local row = vim.api.nvim_win_get_cursor(ct.win)[1]
    local idx = row - ct.header_count
    if idx < 1 or idx > #ct.paths then return end
    local path = ct.paths[idx]
    if vim.fn.filereadable(path) == 0 then
      vim.notify('[pkm] file no longer exists: ' .. vim.fn.fnamemodify(path, ':t'),
        vim.log.levels.WARN)
      return
    end
    local _PANELS = { ['pkm-sidebar'] = true, ['pkm-bufpanel'] = true, ['netrw'] = true }
    local candidates = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= ct.win
      and vim.api.nvim_win_get_config(win).relative == '' then
        if not _PANELS[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
          candidates[#candidates + 1] = { win = win, col = vim.api.nvim_win_get_position(win)[2] }
        end
      end
    end
    local editing_wins = sort_wins_by_col(candidates)
    if #editing_wins == 0 then
      -- No editing windows yet — same fallback as N<CR>'s zero-window case.
      vim.cmd('rightbelow vsplit ' .. vim.fn.fnameescape(path))
      return
    end
    -- Insert immediately right of the sidebar: leftabove of the current
    -- leftmost editing window, so the new window becomes leftmost,
    -- shifting everything else right — the insert-before complement to
    -- N<CR>. Explicit leftabove (not a bare vsplit) so this is
    -- deterministic regardless of the user's 'splitright' setting.
    vim.api.nvim_set_current_win(editing_wins[1].win)
    vim.cmd('leftabove vsplit ' .. vim.fn.fnameescape(path))
  end, ko)

  -- <C-s>: no-op — prevents global split keymaps from acting on the sidebar.
  vim.keymap.set('n', '<C-s>', function() end, ko)

  -- <C-t>: cycle type filter (detail mode only).
  local TYPE_CYCLE = { false, 'note', 'agg', 'bib', 'journal', 'scratch' }
  vim.keymap.set('n', '<C-t>', function()
    local ct = get_tab()
    if ct.mode ~= 'detail' then
      vim.notify('[pkm] type filter only available in detail mode', vim.log.levels.INFO)
      return
    end
    -- Find current position (false = nil sentinel to avoid ipairs stopping early).
    local cur_idx = 1
    for i, v in ipairs(TYPE_CYCLE) do
      if v == (ct.type_filter or false) then cur_idx = i; break end
    end
    local next_idx = (cur_idx % #TYPE_CYCLE) + 1
    local next_val = TYPE_CYCLE[next_idx]
    ct.type_filter = (next_val == false) and nil or next_val
    sidebar_switch_to_detail(ct.name)
    vim.notify('[pkm] type filter: ' .. (ct.type_filter or 'all'), vim.log.levels.INFO)
  end, ko)

  -- T: toggle filename/title display across sidebar and buffer panel
  vim.keymap.set('n', 'T', function()
    local ui_m = require('pkm.ui')
    local mode = ui_m.toggle_display_mode()
    local ct   = get_tab()
    if ct.mode == 'overview' then
      sidebar_switch_to_overview()
    else
      sidebar_switch_to_detail(ct.name)
    end
    ui_m.refresh_bufpanel()
    vim.notify('[pkm] note labels: ' .. mode, vim.log.levels.INFO)
  end, ko)

  -- ?: show sidebar keymap help
  vim.keymap.set('n', '?', sidebar_show_help, ko)

  -- r: refresh current mode in place
  vim.keymap.set('n', 'r', function()
    local ct = get_tab()
    if ct.mode == 'overview' then
      sidebar_switch_to_overview()
    else
      sidebar_switch_to_detail(ct.name)
    end
    vim.notify('[pkm] sidebar refreshed', vim.log.levels.INFO)
  end, ko)

  -- q / <Esc>: close
  local function close_sidebar()
    local ct = get_tab()
    if not (ct.win and vim.api.nvim_win_is_valid(ct.win)) then return end
    -- Count non-float windows; if sidebar is the only one, quit gracefully.
    local non_float = 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).relative == '' then
        non_float = non_float + 1
      end
    end
    if non_float <= 1 then
      vim.cmd('quit')
    else
      vim.api.nvim_win_close(ct.win, true)
    end
  end
  vim.keymap.set('n', 'q',     close_sidebar, ko)
  vim.keymap.set('n', '<Esc>', close_sidebar, ko)

  -- Statusline infobar: show the full filename of the note under the cursor.
  -- In overview mode the statusline is cleared. Fires on every cursor move
  -- within the sidebar buffer; no extra window consumed.
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer   = buf,
    callback = function()
      local ct = get_tab()
      if not (ct.win and vim.api.nvim_win_is_valid(ct.win)) then return end

      local winbar
      if ct.mode == 'detail' then
        local row = vim.api.nvim_win_get_cursor(ct.win)[1]
        local idx = row - ct.header_count
        if idx >= 1 and idx <= #ct.paths then
          local ui_m = require('pkm.ui')
          local e    = require('pkm.index').get(ct.paths[idx])
          if ui_m.get_display_mode() == 'title' and e and e.title and e.title ~= '' then
            winbar = ' ' .. e.title
          else
            local stem = vim.fn.fnamemodify(ct.paths[idx], ':t:r')
            winbar = ' ' .. (e and strip_display_prefix(stem, e.note_type) or stem)
          end
        else
          local filter_label = ct.type_filter and ('  [' .. ct.type_filter .. ']') or ''
          winbar = ' ≡ ' .. (ct.name or '') .. filter_label
        end
      else
        winbar = ''
      end

      vim.api.nvim_set_option_value('winbar', winbar, { win = ct.win })
    end,
  })

  -- Populate initial content
  if name and name ~= '' then
    sidebar_switch_to_detail(name)
  else
    sidebar_switch_to_overview()
  end
end

--- Refresh the sidebar content if it is currently open. No-op otherwise.
--- Call after any operation that modifies the note list (deletion, rename, etc.).
---@return nil
function M.refresh_sidebar_if_open()
  for _, id in ipairs(vim.api.nvim_list_tabpages()) do
    local t = _tabs[id]
    if t and t.win then
      if not vim.api.nvim_win_is_valid(t.win) then
        _tabs[id] = nil
      else
        local lines, view_lines, tree_entries, header_count, sorted
        if t.mode == 'overview' then
          lines, view_lines = sidebar_build_overview()
          t.view_lines = view_lines
      else
          local all_paths = M.match_all(t.name)
          local display_paths = all_paths
          if t.type_filter then
            local idx_m = require('pkm.index')
            local filtered = {}
            for _, p in ipairs(all_paths) do
              local e = idx_m.get(p)
              if e and e.note_type == t.type_filter then
                filtered[#filtered + 1] = p
              end
            end
            display_paths = filtered
          end
          lines, tree_entries, header_count, sorted =
            sidebar_build_lines(t.name, display_paths, #all_paths)
          t.paths        = sorted
          t.tree         = tree_entries
          t.header_count = header_count
        end
        vim.api.nvim_set_option_value('modifiable', true,  { buf = t.buf })
        vim.api.nvim_buf_set_lines(t.buf, 0, -1, false, lines)
        vim.api.nvim_set_option_value('modifiable', false, { buf = t.buf })
      end
    end
  end
end

-- Exposed for test/test_v160_p3.lua only; not part of the module's public API.
M._views_panel          = _views_panel
M._delete_panel         = _delete_panel
M._sort_wins_by_col     = sort_wins_by_col
M._resolve_window_slot  = resolve_window_slot
M._resolve_split_target = resolve_split_target

return M
