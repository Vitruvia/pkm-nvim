-- =============================================================================
-- pkm.views — Named project views over the note index
-- =============================================================================
-- Dependencies : pkm.filter, pkm.index (lazy)
-- Consumed by  : pkm.commands (:PKMView, :PKMViews)
--
-- A view is a named filter expression stored in config.projects. Activating a
-- view runs the filter against the in-memory index and opens the results in a
-- Telescope picker (or a fallback float if Telescope is unavailable).
--
-- Views are read-only projections — they never create, move, or modify notes.
-- The underlying notes remain in the single flat PKM namespace.
--
-- config.projects format:
--   projects = {
--     rpg    = 'tag:rpg AND (title:ringforge OR text:ringforge)',
--     clinic = 'tag:medicine AND tag:protocol AND NOT tag:draft',
--   }
--
-- Public API:
--   list()            → string[]  sorted view names from config
--   match_all(name)   → string[]  paths matching the named view's filter
--   open(name?)       → open view picker; prompts for name if nil
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: Helpers
-- =============================================================================

--- Return the resolved PKM config.
---@return table
local function get_config()
  return require('pkm').config
end

--- Parse and cache filter trees per view name to avoid re-parsing on every call.
local _tree_cache = {}

--- Return the filter tree for a named view, or nil with an error string.
---@param name string
---@return table|nil tree
---@return string|nil err
local function get_tree(name)
  if _tree_cache[name] then return _tree_cache[name], nil end

  local config = get_config()
  local projects = config.projects
  if not projects or not projects[name] then
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

-- =============================================================================
-- SECTION: Public API
-- =============================================================================

--- Return a sorted list of view names defined in config.projects.
---@return string[]
function M.list()
  local config = get_config()
  local projects = config.projects
  if not projects then return {} end

  local names = vim.tbl_keys(projects)
  table.sort(names)
  return names
end

--- Return all note paths matching the named view's filter expression.
--- Returns an empty array if the view does not exist or the filter errors.
---@param name string  View name from config.projects
---@return string[]    Sorted array of absolute paths
function M.match_all(name)
  local tree, err = get_tree(name)
  if not tree then
    vim.notify(err, vim.log.levels.ERROR)
    return {}
  end

  local filter = require('pkm.filter')
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
-- SECTION: Telescope picker
-- =============================================================================

--- Open a Telescope picker showing the notes matched by a view.
--- Uses exact-substring filtering on prompt input (never fzy).
---@param name   string   View name
---@param paths  string[] Pre-matched paths
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
  local title = string.format('PKMView: %s  (%d note%s)',
    name, count, count == 1 and '' or 's')

  pickers.new({}, {
    prompt_title = title,

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

    -- Pass-through sorter: no fzy reordering.
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

-- =============================================================================
-- SECTION: Fallback float picker
-- =============================================================================

--- Open a scrollable floating window listing matched notes.
--- <CR> or <Enter> opens the note under cursor; q/<Esc> closes.
---@param name  string
---@param paths string[]
local function float_view_picker(name, paths)
  if #paths == 0 then
    vim.notify(
      string.format("PKMView '%s': no notes matched.", name),
      vim.log.levels.INFO)
    return
  end

  local lines = {}
  local header = string.format(
    '  View: %s  ·  %d note%s  ·  <CR> open  ·  q/<Esc> close',
    name, #paths, #paths == 1 and '' or 's')
  lines[1] = header
  lines[2] = '  ' .. string.rep('─', math.max(#header - 2, 10))

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

  -- Position cursor on the first note line (line 3, index 2).
  local first_note_line = 3
  if #lines >= first_note_line then
    vim.api.nvim_win_set_cursor(win, { first_note_line, 2 })
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function open_at_cursor()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    -- Rows 1 and 2 are header and separator; notes start at row 3.
    local note_idx = row - 2
    if note_idx < 1 or note_idx > #paths then return end
    close()
    vim.cmd('edit ' .. vim.fn.fnameescape(paths[note_idx]))
  end

  local ko = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set('n', '<CR>',  open_at_cursor, ko)
  vim.keymap.set('n', 'q',     close,          ko)
  vim.keymap.set('n', '<Esc>', close,          ko)
end

-- =============================================================================
-- SECTION: View name picker
-- =============================================================================

--- Let the user choose a view from a picker when no name is given.
--- Opens the selected view after selection.
local function pick_view()
  local names = M.list()
  if #names == 0 then
    vim.notify('PKMView: no views defined in config.projects', vim.log.levels.WARN)
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
-- SECTION: open()
-- =============================================================================

--- Activate a named project view.
--- If name is nil, presents a picker of available views.
--- Runs the view's filter expression against the index and opens results in
--- a Telescope picker (exact-substring prompt, file preview) or a fallback
--- float if Telescope is unavailable.
---@param name string|nil  View name, or nil to prompt
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
