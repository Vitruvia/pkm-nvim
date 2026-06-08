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
--   list_views()        → open tree picker over all views (Telescope or float)
--   edit_view(name?)    → open edit UI for a named view; picker if nil
--   match_all(name)     → string[]  paths matching the named view's filter
--   open(name?)         → activate a view; prompts for name if nil
--   open_last()         → reopen the last activated view (session-scoped)
--   get_last_view()     → active view name for context-aware features (sidebar > last)
--   open_sidebar(name?) → open or toggle the persistent sidebar for a view
--   refresh_sidebar_if_open() → refresh sidebar content if currently open; no-op otherwise
--   save(name, expr)    → write or update a view in views.json
--   save_subproject(name, parent, filter_expr) → write a subproject entry to views.json
--   delete(name)        → remove a view from views.json
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: State
-- =============================================================================

local _sidecar_cache = nil   -- table loaded from views.json; nil when stale
local _tree_cache    = {}    -- name → parsed filter tree
local _last_view = nil          -- name of last successfully activated view

local _sidebar_win   = nil      -- window handle of open sidebar, or nil
local _sidebar_buf   = nil      -- buffer handle of open sidebar, or nil
local _sidebar_name  = nil      -- view name currently shown
local _sidebar_paths = {}       -- path list currently shown
local _sidebar_tree         = {}   -- array of {name, is_current} per tree header line
local _sidebar_header_count = 0    -- total non-note lines (tree header + sep + blank)
local _sidebar_mode       = nil    -- 'overview' | 'detail'
local _sidebar_view_lines = {}     -- overview: 1-based line number → view name
local _sidebar_history    = {}     -- navigation stack: {mode, name} entries

local _TYPE_ORDER = { note = 1, agg = 2, bib = 3, journal = 4, scratch = 5,
other = 6 }

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
  table.sort(children)
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
  for _, children in pairs(children_map) do table.sort(children) end

  local roots = {}
  for name, expr in pairs(projects) do
    local has_parent = type(expr) == 'table'
                       and type(expr.parent) == 'string'
                       and projects[expr.parent] ~= nil
    if not has_parent then roots[#roots + 1] = name end
  end
  table.sort(roots)

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

--- Push current sidebar state onto the navigation history stack.
--- Capped at 50 entries; oldest entry dropped when full.
local function sidebar_push_history()
  if not _sidebar_mode then return end
  if #_sidebar_history >= 50 then
    table.remove(_sidebar_history, 1)
  end
  _sidebar_history[#_sidebar_history + 1] = {
    mode = _sidebar_mode,
    name = _sidebar_name,
  }
end

--- Pop the most recent sidebar state from the history stack.
---@return table|nil  {mode=string, name=string|nil} or nil if empty
local function sidebar_pop_history()
  if #_sidebar_history == 0 then return nil end
  local state = _sidebar_history[#_sidebar_history]
  _sidebar_history[#_sidebar_history] = nil
  return state
end

--- Format a note type as a fixed-width bracket label for display alignment.
---@param note_type string
---@return string  e.g. "[note   ]" or "[journal]"
local function type_prefix(note_type)
  local label = note_type or 'other'
  local width = 7  -- length of 'journal' / 'scratch', the longest types
  local pad   = width - #label
  local lpad  = math.floor(pad / 2) + 1  -- +1 for inner margin
  local rpad  = math.ceil(pad  / 2) + 1
  return '[' .. string.rep(' ', lpad) .. label .. string.rep(' ', rpad) .. ']'
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

  vim.api.nvim_create_autocmd('BufWritePost', {
    group    = augroup,
    pattern  = 'views.json',
    callback = function()
      -- Guard: only invalidate for the PKM views.json, not an unrelated file.
      local written  = vim.fn.expand('<afile>:p'):gsub('\\', '/')
      local root     = get_config().root_path:gsub('\\', '/')
      local expected = root:gsub('[/\\]+$', '') .. '/views.json'
      if written:lower() == expected:lower() then
        invalidate()
        vim.notify('PKMView: views reloaded from views.json', vim.log.levels.INFO)
      end
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
  table.sort(names)
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
  if _sidebar_win and vim.api.nvim_win_is_valid(_sidebar_win)
  and _sidebar_mode == 'detail' and _sidebar_name then
    return _sidebar_name
  end
  return _last_view
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
local function telescope_view_picker(name, paths)
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
      display    = string.format('[ %-7s ] %s  (%d notes)', 'subview', child, c_count),
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
      'PKMView: %s  (%d note%s)  <C-b> views  <C-p> parent  <C-s> subs',
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
        vim.schedule(function() M.list_views() end)
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

      map('i', '<C-b>', go_back)
      map('n', '<C-b>', go_back)
      map('i', '<C-p>', go_parent)
      map('n', '<C-p>', go_parent)
      map('i', '<C-s>', go_children)
      map('n', '<C-s>', go_children)

      return true
    end,
  }):find()
end

--- Scrollable float picker. <CR> opens note at cursor; q/<Esc> closes.
local function float_view_picker(name, paths)
  local index    = require('pkm.index')
  local children = get_view_children(name)
  local sorted   = sort_paths_by_type(paths)

  local header = string.format(
    '  View: %s  ·  %d note%s  ·  <CR> open  ·  <C-b> views  ·  <C-p> parent  ·  <C-s> subs  ·  q close',
    name, #sorted + #children, (#sorted + #children) == 1 and '' or 's')
  local lines       = { header, '  ' .. string.rep('─', math.max(#header - 2, 10)) }
  local line_paths  = {}    -- 1-based line index → path (notes)
  local line_subs   = {}    -- 1-based line index → child name (subviews)

  -- Subviews first
  for _, child in ipairs(children) do
    local c_count = #M.match_all(child)
    lines[#lines + 1] = string.format(
      '  [ %-7s ] %s  (%d notes)', 'subview', child, c_count)
    line_subs[#lines] = child
  end

  if #children > 0 and #sorted > 0 then
    lines[#lines + 1] = '  ' .. string.rep('─', 52)
  end

  -- Notes
  for _, p in ipairs(sorted) do
    local e         = index.get(p)
    local note_type = e and e.note_type or 'other'
    local title     = e and e.title or vim.fn.fnamemodify(p, ':t:r')
    lines[#lines + 1] = '  ' .. type_prefix(note_type) .. ' ' .. title
    line_paths[#lines] = p
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_set_option_value('bufhidden',  'wipe', { buf = buf })

  local width  = math.min(math.max(#header + 4, 60), vim.o.columns - 4)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.7))
  local win    = vim.api.nvim_open_win(buf, true, {
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

  if #lines >= 3 then vim.api.nvim_win_set_cursor(win, { 3, 2 }) end

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
    close(); vim.schedule(function() M.list_views() end)
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

  local ko = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set('n', '<CR>',  open_at_cursor, ko)
  vim.keymap.set('n', '<C-b>', go_back,        ko)
  vim.keymap.set('n', '<C-p>', go_parent,      ko)
  vim.keymap.set('n', '<C-s>', go_children,    ko)
  vim.keymap.set('n', 'q',     close,          ko)
  vim.keymap.set('n', '<Esc>', close,          ko)
end

--- Telescope tree picker over all defined views.
--- Selecting a view opens it via M.open(). Uses generic_sorter (fzy is
--- appropriate here — we are matching short view names, not structured content).
local function telescope_views_tree_picker()
  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local sorters      = require('telescope.sorters')
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  local tree  = build_tree_entries()
  local items = {}

  for _, e in ipairs(tree) do
    local count  = #M.match_all(e.name)
    local indent = string.rep('  ', e.depth)
    local marker = e.has_children and '▶ ' or '• '
    items[#items + 1] = {
      name    = e.name,
      display = string.format('%s%s%s  (%d)', indent, marker, e.name, count),
      ordinal = string.format('%05d', #items + 1),
    }
  end

  if #items == 0 then
    vim.notify('[pkm] no views defined. Use :PKMViewNew to create one.', vim.log.levels.WARN)
    return
  end

  pickers.new({
    sorting_strategy = 'ascending',
    layout_config    = { prompt_position = 'top' },
  }, {
    prompt_title = 'PKM Views  ·  <C-f> search view',
    finder = finders.new_dynamic {
      fn = function(prompt)
        if not prompt or prompt == '' then return items end
        local needle = prompt:lower()
        local out = {}
        for _, item in ipairs(items) do
          if item.name:lower():find(needle, 1, true) then
            out[#out + 1] = item
          end
        end
        return out
      end,
      entry_maker = function(item)
        return { value = item.name, display = item.display, ordinal = item.ordinal }
      end,
    },
    sorter = sorters.empty(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local sel = action_state.get_selected_entry()
        if sel then M.open(sel.value) end
      end)

      local function search_current()
        local sel = action_state.get_selected_entry()
        if not sel then return end
        actions.close(prompt_bufnr)
        vim.schedule(function()
          local paths = M.match_all(sel.value)
          local title = string.format('Search: %s', sel.value)
          local has_tele = pcall(require, 'telescope')
          if has_tele then
            require('pkm.telescope').browse_paths(title, paths)
          else
            require('pkm.ui').browse_paths(title, paths)
          end
        end)
      end

      map('i', '<C-f>', search_current)
      map('n', '<C-f>', search_current)

      return true
    end,
  }):find()
end

--- Scrollable float tree picker over all defined views.
--- <CR> opens the view under the cursor; q/<Esc> closes.
local function float_views_tree_picker()
  local tree = build_tree_entries()

  if #tree == 0 then
    vim.notify('[pkm] no views defined. Use :PKMViewNew to create one.', vim.log.levels.WARN)
    return
  end

  local header = '  PKM Views  ·  <CR> open  ·  <C-f> search  ·  q/<Esc> close'
  local lines  = { header, '  ' .. string.rep('─', math.max(#header - 2, 20)) }
  local names  = {}  -- line number → view name (only view lines, not header)

  for _, e in ipairs(tree) do
    local count  = #M.match_all(e.name)
    local indent = string.rep('  ', e.depth)
    local marker = e.has_children and '▶ ' or '• '
    lines[#lines + 1] = string.format('  %s%s%s  (%d)', indent, marker, e.name, count)
    names[#lines]     = e.name
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_set_option_value('bufhidden',  'wipe', { buf = buf })

  local width  = math.min(72, vim.o.columns - 4)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.7))
  local win    = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    width     = width,
    height    = height,
    col       = math.floor((vim.o.columns - width)  / 2),
    row       = math.floor((vim.o.lines   - height) / 2),
    style     = 'minimal',
    border    = 'rounded',
    title     = ' PKM Views ',
    title_pos = 'center',
  })

  if #lines >= 3 then vim.api.nvim_win_set_cursor(win, { 3, 0 }) end

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  local ko = { noremap = true, silent = true, buffer = buf }

  vim.keymap.set('n', '<CR>', function()
    local name = names[vim.api.nvim_win_get_cursor(win)[1]]
    if name then close(); M.open(name) end
  end, ko)

  vim.keymap.set('n', '<C-f>', function()
    local name = names[vim.api.nvim_win_get_cursor(win)[1]]
    if not name then return end
    close()
    vim.schedule(function()
      local paths = M.match_all(name)
      local title = string.format('Search: %s', name)
      local has_tele = pcall(require, 'telescope')
      if has_tele then
        require('pkm.telescope').browse_paths(title, paths)
      else
        require('pkm.ui').browse_paths(title, paths)
      end
    end)
  end, ko)

  vim.keymap.set('n', 'q',     close, ko)
  vim.keymap.set('n', '<Esc>', close, ko)
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

  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    telescope_view_picker(name, paths)
  else
    float_view_picker(name, paths)
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

--- Open the views tree picker showing all views in parent-child hierarchy.
--- Telescope picker when available; scrollable float otherwise.
--- Selecting a view opens it via M.open().
---@return nil
function M.list_views()
  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    telescope_views_tree_picker()
  else
    float_views_tree_picker()
  end
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

--- Open an edit UI for a named view.
--- If name is nil, presents a picker of all defined views.
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
      if sel then edit_view_float(sel) end
    end)
    return
  end
  edit_view_float(name)
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
local function sidebar_build_lines(name, paths)
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
    lines[#lines + 1] = '  PKMView: ' .. name
      .. '  (' .. count .. ' note' .. (count == 1 and '' or 's') .. ')'
    lines[#lines + 1] = '  ' .. string.rep('─', 38)
    lines[#lines + 1] = ''
  end

  local header_count = #lines
  local sorted       = sort_paths_by_type(paths)

  for i, path in ipairs(sorted) do
    local entry     = index.get(path)
    local note_type = entry and entry.note_type or 'other'
    local title     = entry and entry.title or vim.fn.fnamemodify(path, ':t:r')
    lines[#lines + 1] = string.format('  %3d  %s %s', i, type_prefix(note_type), title)
  end
  if #sorted == 0 then
    lines[#lines + 1] = '  (no notes match)'
  end

  return lines, tree_entries, header_count, sorted
end

--- Write lines to the sidebar buffer.
local function sidebar_set_content(lines)
  vim.api.nvim_set_option_value('modifiable', true,  { buf = _sidebar_buf })
  vim.api.nvim_buf_set_lines(_sidebar_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = _sidebar_buf })
end

--- Switch the open sidebar to overview mode.
local function sidebar_switch_to_overview()
  local lines, view_lines = sidebar_build_overview()
  _sidebar_mode         = 'overview'
  _sidebar_name         = nil
  _sidebar_paths        = {}
  _sidebar_tree         = {}
  _sidebar_header_count = 0
  _sidebar_view_lines   = view_lines
  sidebar_set_content(lines)
  if vim.api.nvim_win_is_valid(_sidebar_win) then
    vim.api.nvim_win_set_cursor(_sidebar_win, { math.min(4, vim.api.nvim_buf_line_count(_sidebar_buf)), 0 })
  end
end

--- Switch the open sidebar to detail mode for a named view.
---@param name string
local function sidebar_switch_to_detail(name)
  local paths = M.match_all(name)
  local lines, tree_entries, header_count, sorted =
    sidebar_build_lines(name, paths)
  _sidebar_mode         = 'detail'
  _sidebar_name         = name
  _sidebar_paths        = sorted
  _sidebar_tree         = tree_entries
  _sidebar_header_count = header_count
  _sidebar_view_lines   = {}
  sidebar_set_content(lines)
  if vim.api.nvim_win_is_valid(_sidebar_win) and #sorted > 0 then
    vim.api.nvim_win_set_cursor(_sidebar_win, { header_count + 1, 0 })
  end
end

--- Open a compact help float listing all sidebar keymaps.
local function sidebar_show_help()
  local lines = {
    '  <CR>    open note / enter view',
    '  b       back (pop history)',
    '  <BS>    same as b',
    '  <C-b>   jump to overview',
    '  /       search in current view',
    '  r       refresh',
    '  q       close sidebar',
    '  ?       this help',
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_set_option_value('bufhidden',  'wipe', { buf = buf })

  local width  = 36
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
  -- Clear stale state if the window was destroyed externally
  if _sidebar_win and not vim.api.nvim_win_is_valid(_sidebar_win) then
    _sidebar_win = nil; _sidebar_buf = nil
    _sidebar_mode = nil; _sidebar_name = nil; _sidebar_paths = {}
    _sidebar_tree = {}; _sidebar_header_count = 0
    _sidebar_view_lines = {}; _sidebar_history = {}
  end

  if not name or name == '' then
    -- No name: close if open, else open in overview
    if _sidebar_win then
      vim.api.nvim_win_close(_sidebar_win, true)
      return
    end
  else
    -- Named: operate on existing sidebar
    if _sidebar_win then
      if _sidebar_mode == 'detail' and _sidebar_name == name then
        vim.api.nvim_win_close(_sidebar_win, true)
        return
      end
      sidebar_push_history()
      sidebar_switch_to_detail(name)
      return
    end
  end

  -- Open new sidebar window
  local prev_win = vim.api.nvim_get_current_win()
  local width    = (require('pkm').config.sidebar_width or 40)

  vim.cmd('noautocmd topleft vsplit')
  _sidebar_win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  _sidebar_buf = buf
  vim.api.nvim_win_set_buf(_sidebar_win, buf)
  vim.api.nvim_win_set_width(_sidebar_win, width)

  for opt, val in pairs({
    winfixwidth = true, wrap = false,
    number = false, cursorline = true, signcolumn = 'no',
  }) do
    vim.api.nvim_set_option_value(opt, val, { win = _sidebar_win })
  end

  for opt, val in pairs({
    bufhidden = 'wipe', buftype = 'nofile', swapfile = false,
  }) do
    vim.api.nvim_set_option_value(opt, val, { buf = buf })
  end

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer   = buf,
    once     = true,
    callback = function()
      _sidebar_win = nil; _sidebar_buf = nil
      _sidebar_mode = nil; _sidebar_name = nil; _sidebar_paths = {}
      _sidebar_tree = {}; _sidebar_header_count = 0
      _sidebar_view_lines = {}; _sidebar_history = {}
    end,
  })

  local ko = { noremap = true, silent = true, buffer = buf }

  -- <CR>: mode-aware action
  vim.keymap.set('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(_sidebar_win)[1]

    if _sidebar_mode == 'overview' then
      local vname = _sidebar_view_lines[row]
      if vname then
        sidebar_push_history()
        sidebar_switch_to_detail(vname)
      end
      return
    end

    -- detail: tree header line → navigate to that view
    local te = _sidebar_tree[row]
    if te then
      if not te.is_current then
        sidebar_push_history()
        sidebar_switch_to_detail(te.name)
      end
      return
    end

    -- detail: note line → open in main window
    local idx = row - _sidebar_header_count
    if idx < 1 or idx > #_sidebar_paths then return end
    local path = _sidebar_paths[idx]

    if vim.fn.filereadable(path) == 0 then
      vim.notify(
        '[pkm] file no longer exists: ' .. vim.fn.fnamemodify(path, ':t'),
        vim.log.levels.WARN
      )
      return
    end

    local target
    local alt_id = vim.fn.win_getid(vim.fn.winnr('#'))
    if alt_id ~= 0 and alt_id ~= _sidebar_win
    and vim.api.nvim_win_is_valid(alt_id)
    and vim.api.nvim_win_get_config(alt_id).relative == '' then
      target = alt_id
    end
    if not target then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= _sidebar_win
        and vim.api.nvim_win_get_config(win).relative == '' then
          target = win; break
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
    elseif _sidebar_mode == 'overview' then
      vim.notify('[pkm] already at views overview', vim.log.levels.INFO)
    else
      sidebar_switch_to_overview()
    end
  end, ko)

  -- <C-b>: jump directly to overview, push current to history
  vim.keymap.set('n', '<C-b>', function()
    if _sidebar_mode ~= 'overview' then
      sidebar_push_history()
      sidebar_switch_to_overview()
    end
  end, ko)

  -- b: explicit back key — reliable alternative to <BS> on all terminals
  vim.keymap.set('n', 'b', function()
    local state = sidebar_pop_history()
    if state then
      if state.mode == 'overview' then
        sidebar_switch_to_overview()
      else
        sidebar_switch_to_detail(state.name)
      end
    elseif _sidebar_mode == 'overview' then
      vim.notify('[pkm] already at views overview', vim.log.levels.INFO)
    else
      sidebar_switch_to_overview()
    end
  end, ko)

  -- /: scoped search — detail searches current view paths; overview does full browse
  vim.keymap.set('n', '/', function()
    local has_tele = pcall(require, 'telescope')
    if _sidebar_mode == 'detail' then
      local title = string.format('Search: %s', _sidebar_name)
      if has_tele then
        require('pkm.telescope').browse_paths(title, _sidebar_paths)
      else
        require('pkm.ui').browse_paths(title, _sidebar_paths)
      end
    else
      if has_tele then
        require('pkm.telescope').browse()
      else
        require('pkm.ui').browse()
      end
    end
  end, ko)

  -- ?: show sidebar keymap help
  vim.keymap.set('n', '?', sidebar_show_help, ko)

  -- r: refresh current mode in place
  vim.keymap.set('n', 'r', function()
    if _sidebar_mode == 'overview' then
      sidebar_switch_to_overview()
    else
      sidebar_switch_to_detail(_sidebar_name)
    end
    vim.notify('[pkm] sidebar refreshed', vim.log.levels.INFO)
  end, ko)

  -- q / <Esc>: close
  local function close_sidebar()
    if _sidebar_win and vim.api.nvim_win_is_valid(_sidebar_win) then
      vim.api.nvim_win_close(_sidebar_win, true)
    end
  end
  vim.keymap.set('n', 'q',     close_sidebar, ko)
  vim.keymap.set('n', '<Esc>', close_sidebar, ko)

  -- Populate initial content
  if name and name ~= '' then
    sidebar_switch_to_detail(name)
  else
    sidebar_switch_to_overview()
  end

  vim.api.nvim_set_current_win(prev_win)
end

--- Refresh the sidebar content if it is currently open. No-op otherwise.
--- Call after any operation that modifies the note list (deletion, rename, etc.).
---@return nil
function M.refresh_sidebar_if_open()
  if not _sidebar_win then return end
  if not vim.api.nvim_win_is_valid(_sidebar_win) then
    _sidebar_win = nil
    return
  end
  if _sidebar_mode == 'overview' then
    sidebar_switch_to_overview()
  else
    sidebar_switch_to_detail(_sidebar_name)
  end
end

return M
