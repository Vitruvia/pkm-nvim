-- =============================================================================
-- pkm.views — Named project views over the note index
-- =============================================================================
-- Dependencies : pkm.filter, pkm.index (lazy), pkm.utils
-- Consumed by  : pkm.commands (:PKMView, :PKMViews, :PKMViewNew,
--                :PKMViewEdit, :PKMViewDelete)
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
--   match_all(name)     → string[]  paths matching the named view's filter
--   open(name?)         → activate a view; prompts for name if nil
--   open_last()         → reopen the last activated view (session-scoped)
--   open_sidebar(name?) → open or toggle the persistent sidebar for a view
--   save(name, expr)    → write or update a view in views.json
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

  local entries = {}
  for _, path in ipairs(paths) do
    local display = vim.fn.fnamemodify(path, ':t')
    entries[#entries + 1] = {
      value   = path,
      display = display,
      ordinal = display,
      path    = path,
    }
  end

  local count = #entries
  pickers.new({}, {
    prompt_title = string.format('PKMView: %s  (%d note%s)',
      name, count, count == 1 and '' or 's'),

    finder = finders.new_dynamic({
      fn = function(prompt)
        if not prompt or prompt == '' then return entries end
        local needle   = prompt:lower()
        local filtered = {}
        for _, e in ipairs(entries) do
          if e.ordinal:lower():find(needle, 1, true) then
            filtered[#filtered + 1] = e
          end
        end
        return filtered
      end,
      entry_maker = function(e) return e end,
    }),

    -- Pass-through sorter: prevents any fzy reordering.
    sorter = sorters.Sorter:new({
      scoring_function = function() return 0 end,
    }),

    previewer = previewers.vim_buffer_cat.new({}),

    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          vim.cmd('edit ' .. vim.fn.fnameescape(entry.value))
        end
      end)
      return true
    end,
  }):find()
end

--- Scrollable float picker. <CR> opens note at cursor; q/<Esc> closes.
local function float_view_picker(name, paths)
  local header = string.format(
    '  View: %s  ·  %d note%s  ·  <CR> open  ·  q/<Esc> close',
    name, #paths, #paths == 1 and '' or 's')
  local lines = {
    header,
    '  ' .. string.rep('─', math.max(#header - 2, 10)),
  }
  for _, p in ipairs(paths) do
    lines[#lines + 1] = '  ' .. vim.fn.fnamemodify(p, ':t')
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_set_option_value('bufhidden',  'wipe', { buf = buf })

  local width  = math.min(84, vim.o.columns - 4)
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

  -- Place cursor on the first note line (row 3; rows 1-2 are header/separator).
  if #lines >= 3 then
    vim.api.nvim_win_set_cursor(win, { 3, 2 })
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function open_at_cursor()
    local row      = vim.api.nvim_win_get_cursor(win)[1]
    local note_idx = row - 2   -- rows 1-2 are header/separator
    if note_idx < 1 or note_idx > #paths then return end
    close()
    vim.cmd('edit ' .. vim.fn.fnameescape(paths[note_idx]))
  end

  local ko = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set('n', '<CR>',  open_at_cursor, ko)
  vim.keymap.set('n', 'q',     close,          ko)
  vim.keymap.set('n', '<Esc>', close,          ko)
end

--- Telescope tree picker over all defined views.
--- Selecting a view opens it via M.open(). Uses generic_sorter (fzy is
--- appropriate here — we are matching short view names, not structured content).
local function telescope_views_tree_picker()
  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local conf         = require('telescope.config').values
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  local tree    = build_tree_entries()
  local entries = {}

  for _, e in ipairs(tree) do
    local count  = #M.match_all(e.name)
    local indent = string.rep('  ', e.depth)
    local marker = e.has_children and '▶ ' or '• '
    entries[#entries + 1] = {
      name    = e.name,
      display = string.format('%s%s%s  (%d)', indent, marker, e.name, count),
      ordinal = e.name,
    }
  end

  if #entries == 0 then
    vim.notify('[pkm] no views defined. Use :PKMViewNew to create one.', vim.log.levels.WARN)
    return
  end

  pickers.new({}, {
    prompt_title = 'PKM Views',
    finder = finders.new_table {
      results = entries,
      entry_maker = function(e)
        return { value = e.name, display = e.display, ordinal = e.ordinal }
      end,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local sel = action_state.get_selected_entry()
        if sel then M.open(sel.value) end
      end)
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

  local header = '  PKM Views  ·  <CR> open  ·  q/<Esc> close'
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
-- SECTION: Sidebar
-- =============================================================================

--- Build the display lines for the sidebar buffer.
--- Returns lines, tree_entries, header_count.
--- tree_entries: array of {name, is_current} indexed by line number (1-based).
--- header_count: number of lines before the first note entry.
---@param name  string
---@param paths string[]
---@return string[], table, integer
local function sidebar_build_lines(name, paths)
  local index    = require('pkm.index')
  local parent   = get_view_parent(name)
  local children = get_view_children(name)
  local lines    = {}
  local tree_entries = {}

  if parent or #children > 0 then
    -- Tree header: parent (if any), current, children
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
    -- Simple header when no hierarchy exists
    local count = #paths
    lines[#lines + 1] = '  PKMView: ' .. name
      .. '  (' .. count .. ' note' .. (count == 1 and '' or 's') .. ')'
    lines[#lines + 1] = '  ' .. string.rep('─', 38)
    lines[#lines + 1] = ''
  end

  local header_count = #lines

  for i, path in ipairs(paths) do
    local entry = index.get(path)
    local title = entry and entry.title or vim.fn.fnamemodify(path, ':t:r')
    lines[#lines + 1] = string.format('  %3d  %s', i, title)
  end
  if #paths == 0 then
    lines[#lines + 1] = '  (no notes match)'
  end

  return lines, tree_entries, header_count
end

--- Open or toggle the persistent view sidebar.
--- nil/'' with sidebar open → close. nil/'' with sidebar closed → prompt.
--- Same name called again → close. Different name → replace contents.
--- Tree header (when view has parent/children): <CR> navigates to that view.
--- <CR> on note line opens note in alternate window. <BS> navigates to parent.
--- r refreshes against the current index. q/<Esc> closes.
---@param name string|nil
---@return nil
function M.open_sidebar(name)
  -- Clear stale state if the window was destroyed externally
  if _sidebar_win and not vim.api.nvim_win_is_valid(_sidebar_win) then
    _sidebar_win = nil; _sidebar_buf = nil
    _sidebar_name = nil; _sidebar_paths = {}
    _sidebar_tree = {}; _sidebar_header_count = 0
  end

  -- No name: close if open, else prompt
  if not name or name == '' then
    if _sidebar_win then
      vim.api.nvim_win_close(_sidebar_win, true)
      return
    end
    local names = M.list()
    if #names == 0 then
      vim.notify('[pkm] no views defined. Use :PKMViewNew to create one.', vim.log.levels.WARN)
      return
    end
    vim.ui.select(names, {
      prompt      = 'Open sidebar for view:',
      format_item = function(n) return n end,
    }, function(sel)
      if sel then M.open_sidebar(sel) end
    end)
    return
  end

  -- Toggle: same view → close
  if _sidebar_win and _sidebar_name == name then
    vim.api.nvim_win_close(_sidebar_win, true)
    return
  end

  local paths = M.match_all(name)
  _sidebar_name  = name
  _sidebar_paths = paths

  local lines, tree_entries, header_count = sidebar_build_lines(name, paths)
  _sidebar_tree         = tree_entries
  _sidebar_header_count = header_count

  -- Replace contents when sidebar is already open for a different view
  if _sidebar_win then
    vim.api.nvim_set_option_value('modifiable', true,  { buf = _sidebar_buf })
    vim.api.nvim_buf_set_lines(_sidebar_buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = _sidebar_buf })
    if #paths > 0 then
      vim.api.nvim_win_set_cursor(_sidebar_win, { header_count + 1, 0 })
    end
    return
  end

  -- Open new sidebar window at the far left (full height)
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

  vim.api.nvim_set_option_value('modifiable', true,  { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

  if #paths > 0 then
    vim.api.nvim_win_set_cursor(_sidebar_win, { header_count + 1, 0 })
  end

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer   = buf,
    once     = true,
    callback = function()
      _sidebar_win = nil; _sidebar_buf = nil
      _sidebar_name = nil; _sidebar_paths = {}
      _sidebar_tree = {}; _sidebar_header_count = 0
    end,
  })

  local ko = { noremap = true, silent = true, buffer = buf }

  -- <CR>: tree header line → navigate to that view; note line → open note
  vim.keymap.set('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(_sidebar_win)[1]

    -- Tree header line
    local te = _sidebar_tree[row]
    if te then
      if not te.is_current then M.open_sidebar(te.name) end
      return
    end

    -- Note line
    local idx = row - _sidebar_header_count
    if idx < 1 or idx > #_sidebar_paths then return end
    local path = _sidebar_paths[idx]

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

  -- <BS>: navigate to parent view
  vim.keymap.set('n', '<BS>', function()
    local parent = get_view_parent(_sidebar_name)
    if parent then
      M.open_sidebar(parent)
    else
      vim.notify('[pkm] this view has no parent', vim.log.levels.INFO)
    end
  end, ko)

  -- r: refresh against current index
  vim.keymap.set('n', 'r', function()
    _sidebar_paths = M.match_all(_sidebar_name)
    local new_lines, new_tree, new_hcount =
      sidebar_build_lines(_sidebar_name, _sidebar_paths)
    _sidebar_tree         = new_tree
    _sidebar_header_count = new_hcount
    vim.api.nvim_set_option_value('modifiable', true,  { buf = _sidebar_buf })
    vim.api.nvim_buf_set_lines(_sidebar_buf, 0, -1, false, new_lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = _sidebar_buf })
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

  vim.api.nvim_set_current_win(prev_win)
end

return M
