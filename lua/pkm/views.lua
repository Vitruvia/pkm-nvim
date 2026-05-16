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
-- views.json format:
--   {
--     "rpg":    "tag:rpg AND (title:ringforge OR text:ringforge)",
--     "clinic": "tag:medicine AND tag:protocol AND NOT tag:draft"
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
--   match_all(name)     → string[]  paths matching the named view's filter
--   open(name?)         → activate a view; prompts for name if nil
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

--- Parse and cache the filter tree for a named view.
---@param name string
---@return table|nil tree
---@return string|nil err
local function get_tree(name)
  if _tree_cache[name] then return _tree_cache[name], nil end

  local projects = get_projects()
  if not projects[name] then
    return nil, string.format("PKMView: no view named '%s'", name)
  end

  local expr = projects[name]
  if type(expr) ~= 'string' or expr:match('^%s*$') then
    return nil, string.format("PKMView: view '%s' has an empty filter expression", name)
  end

  local filter = require('pkm.filter')
  local tree, err = filter.parse(expr)
  if not tree then
    return nil, string.format("PKMView: parse error in view '%s': %s", name, err)
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

  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    telescope_view_picker(name, paths)
  else
    float_view_picker(name, paths)
  end
end

return M
