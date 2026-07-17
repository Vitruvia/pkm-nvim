-- =============================================================================
-- pkm.ui — Fallback UI components (no Telescope dependency)
-- =============================================================================
-- Dependencies : pkm.yaml, pkm.utils, pkm.panel, pkm.citations (lazy),
--                pkm.index (lazy), pkm.views (lazy)
-- Consumed by  : pkm.commands, pkm.telescope (fallback)
--
-- Buffer panel and tag panel are both built on pkm.panel.create() (v1.6.0
-- Phase 1). This module owns each panel's build_lines/keymaps/mode-specific
-- logic; panel.lua owns the shared window/buffer/augroup lifecycle.
--
-- Public API:
--   setup(user_config)        → Initialize with resolved PKM config
--   browse_tags()              → Two-level tag → file picker
--   browse(filter_expr?)       → Prompt for filter expression, eval, vim.ui.select results
--   browse_paths(title, paths) → Show scoped path list via vim.ui.select (sorted)
--   browse_recent(n?)          → n most-recently-modified notes via vim.ui.select
--   insert_citation_ui()       → Context-aware citation picker fallback (no Telescope);
--                                 sorted by view membership and shared tags
--   merge_tags_ui()            → Interactive tag merge (fallback for PKMMergeTags)
--   show_stats()               → Show note counts via vim.notify
--   get_display_mode()         → 'filename' | 'title'
--   toggle_display_mode()      → toggle and return new mode
--   refresh_bufpanel()         → refresh panel from outside
--   toggle_bufpanel()          → toggle the persistent bottom buffer-list panel (per-tabpage)
--   is_bufpanel_open()         → boolean, whether buffer panel is open in current tabpage
--   open_tag_panel(mode)       → open searchable add/remove tag panel ('add'|'remove')
-- =============================================================================
local M = {}

local utils = require('pkm.utils')
local panel = require('pkm.panel')
local config = {}
local _display_mode = 'filename'  -- 'filename' | 'title'

-- Session-scoped "last opened" order, used only for buffers not currently
-- shown in any editing window. Incremented on every BufEnter into a real,
-- listed buffer; higher = more recently opened. Per-session by design --
-- never persisted, matching the buffer panel's own scope (organizing only
-- the current session, not history across restarts).
local _open_order   = {}
local _open_counter = 0

local _TYPE_ORDER = { note = 1, agg = 2, bib = 3, journal = 4, scratch = 5, other = 6 }
local _TYPE_ABBREV = {
  note    = 'n',
  agg     = 'a',
  bib     = 'b',
  journal = 'j',
  scratch = 's',
  other   = 'o',
  file    = 'f',
}

local function type_prefix(note_type)
  return '[' .. (_TYPE_ABBREV[note_type or 'other'] or 'o') .. ']'
end

local function strip_display_prefix(filename, note_type)
  if note_type == 'journal' or note_type == 'scratch' then
    return filename:match('^%a+_(.+)$') or filename
  elseif note_type == 'note' or note_type == 'agg' or note_type == 'bib' then
    return filename:match('^%d+_%a+_(.+)$') or filename
  end
  return filename
end

-- =============================================================================
-- SECTION: Buffer panel
-- =============================================================================

--- Build buffer panel display lines.
---@param state table  This panel's per-tab state (from pkm.panel)
---@return string[], table  lines, buf_map (1-based line → bufnr)
local function bufpanel_build_lines(state)
  local index  = require('pkm.index')
  local listed = {}

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= state.buf
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ''
    and vim.bo[bufnr].filetype ~= 'netrw'
    and vim.fn.isdirectory(vim.api.nvim_buf_get_name(bufnr)) == 0 then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= '' then listed[#listed + 1] = bufnr end
    end
  end

  -- Window labels + leftmost column per buffer, from one walk: a buffer
  -- showing in more than one window uses its leftmost window's column for
  -- ordering. nvim_tabpage_list_wins' own order isn't guaranteed to be
  -- column order for mixed horizontal/vertical layouts, so window numbers
  -- are assigned after an explicit left-to-right sort -- same convention
  -- views.lua's sort_wins_by_col established for N<CR>/<C-v>.
  local win_labels  = {}
  local win_col     = {}   -- bufnr -> leftmost column among its windows
  local win_entries = {}   -- {win, col, bufnr}[]
  local _PANEL_FT  = { ['pkm-sidebar'] = true, ['pkm-bufpanel'] = true, ['netrw'] = true }
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == '' then
      if not _PANEL_FT[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
        local wbuf = vim.api.nvim_win_get_buf(win)
        local col  = vim.api.nvim_win_get_position(win)[2]
        win_entries[#win_entries + 1] = { win = win, col = col, bufnr = wbuf }
        if not win_col[wbuf] or col < win_col[wbuf] then win_col[wbuf] = col end
      end
    end
  end
  table.sort(win_entries, function(a, b) return a.col < b.col end)
  for i, e in ipairs(win_entries) do
    if not win_labels[e.bufnr] then win_labels[e.bufnr] = {} end
    table.insert(win_labels[e.bufnr], '<- w' .. i)
  end

  -- Order: buffers currently in a window first (leftmost window first),
  -- then buffers not in any window, most-recently-opened first. Per
  -- session only -- _open_order is never persisted.
  table.sort(listed, function(a, b)
    local ca, cb = win_col[a], win_col[b]
    if ca and cb then return ca < cb end
    if ca and not cb then return true end
    if cb and not ca then return false end
    return (_open_order[a] or 0) > (_open_order[b] or 0)
  end)

  local lines   = { '  Buffers  (' .. #listed .. ')  <CR> open  d close  D force  w save+close  r refresh  T title  q close' }
  local buf_map = {}

  for _, bufnr in ipairs(listed) do
    local name     = vim.api.nvim_buf_get_name(bufnr)
    local modified = vim.bo[bufnr].modified and ' [+]' or ''
    local wlabel   = win_labels[bufnr]
                     and (' ' .. table.concat(win_labels[bufnr], ','))
                     or ''
    local entry    = index.get(name)
    local display
    if entry then
      local label
      if _display_mode == 'title' and entry.title and entry.title ~= '' then
        label = entry.title
      else
        label = strip_display_prefix(entry.filename, entry.note_type)
      end
      display = string.format('  %s %s%s%s',
        type_prefix(entry.note_type), label, wlabel, modified)
    else
      display = string.format('  %s %s%s%s',
        type_prefix('file'), vim.fn.fnamemodify(name, ':t'), wlabel, modified)
    end
    lines[#lines + 1] = display
    buf_map[#lines]   = bufnr
  end

  if #listed == 0 then lines[#lines + 1] = '  (no open buffers)' end
  return lines, buf_map
end

--- Switch all non-panel, non-float windows in the current tabpage that
--- are showing bufnr away from it before a bdelete call.
--- Prefers the window's alternate buffer; falls back to any other listed
--- buffer; last resort is a new empty buffer. Prevents bdelete from
--- closing windows unintentionally.
---@param bufnr integer
---@param panel_win integer  the buffer panel's own window, to exclude
local function detach_buf_from_wins(bufnr, panel_win)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= panel_win
    and vim.api.nvim_win_get_config(win).relative == ''
    and vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_win_call(win, function()
        local alt = vim.fn.bufnr('#')
        if alt > 0 and alt ~= bufnr
        and vim.api.nvim_buf_is_valid(alt)
        and vim.bo[alt].buflisted then
          vim.cmd('noautocmd buffer ' .. alt)
          return
        end
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if b ~= bufnr
          and vim.api.nvim_buf_is_valid(b)
          and vim.bo[b].buflisted
          and vim.api.nvim_buf_get_name(b) ~= '' then
            vim.cmd('noautocmd buffer ' .. b)
            return
          end
        end
        vim.cmd('noautocmd enew')
      end)
    end
  end
end

local _bufpanel = panel.create({
  name           = 'bufpanel',
  split_cmd      = 'noautocmd botright split',
  win_opts       = { winfixheight = true, colorcolumn = '' },
  refresh_events = { 'BufAdd', 'BufDelete', 'BufWipeout', 'BufModifiedSet', 'BufEnter' },
  focus_on_open  = false,  -- glanceable, not modal — matches pre-port behaviour
  build_lines    = bufpanel_build_lines,
  resize = function(state, lines)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_height(state.win, math.min(#lines + 1, 8))
    end
  end,
  keymaps = {
    ['<CR>'] = function(state)
      local bufnr = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

      local _PANELS = { ['pkm-sidebar'] = true, ['pkm-bufpanel'] = true, ['netrw'] = true }
      local target
      local alt_id = vim.fn.win_getid(vim.fn.winnr('#'))
      if alt_id ~= 0 and alt_id ~= state.win
      and vim.api.nvim_win_is_valid(alt_id)
      and vim.api.nvim_win_get_config(alt_id).relative == '' then
        if not _PANELS[vim.bo[vim.api.nvim_win_get_buf(alt_id)].filetype] then
          target = alt_id
        end
      end
      if not target then
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if win ~= state.win
          and vim.api.nvim_win_get_config(win).relative == '' then
            if not _PANELS[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
              target = win; break
            end
          end
        end
      end
      if target then
        vim.api.nvim_set_current_win(target)
        vim.api.nvim_set_current_buf(bufnr)
      else
        vim.api.nvim_set_current_win(state.win)
        vim.cmd('aboveleft new')
        vim.bo.bufhidden = 'wipe'
        vim.api.nvim_set_current_buf(bufnr)
      end
    end,

    ['d'] = function(state, helpers)
      local bufnr = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

      if vim.bo[bufnr].modified then
        local name  = vim.api.nvim_buf_get_name(bufnr)
        local label = name ~= '' and vim.fn.fnamemodify(name, ':t') or '[No Name]'
        local choice = vim.fn.confirm(
          string.format("Save changes to '%s' before closing?", label),
          '&Yes\n&No\n&Cancel', 1)
        if choice ~= 1 and choice ~= 2 then
          return
        end
        if choice == 1 then
          local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd('write') end)
          if not ok then
            vim.notify('[pkm] write failed: ' .. (err or ''), vim.log.levels.ERROR)
            return
          end
        end
      end

      detach_buf_from_wins(bufnr, state.win)
      local force = vim.bo[bufnr].modified and '!' or ''
      local ok, err = pcall(vim.cmd, 'bdelete' .. force .. ' ' .. bufnr)
      if not ok then
        vim.notify('[pkm] ' .. (err or 'cannot close buffer'), vim.log.levels.WARN)
      else
        helpers.ensure_main_window()
      end
    end,

    ['D'] = function(state, helpers)
      local bufnr = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
      detach_buf_from_wins(bufnr, state.win)
      local ok, err = pcall(vim.cmd, 'bdelete! ' .. bufnr)
      if not ok then
        vim.notify('[pkm] ' .. (err or 'cannot close buffer'), vim.log.levels.WARN)
      else
        helpers.ensure_main_window()
      end
    end,

    ['w'] = function(state, helpers)
      local bufnr = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
      local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
        vim.cmd('write')
      end)
      if not ok then
        vim.notify('[pkm] write failed: ' .. (err or ''), vim.log.levels.ERROR)
        return
      end
      detach_buf_from_wins(bufnr, state.win)
      pcall(vim.cmd, 'bdelete ' .. bufnr)
      helpers.ensure_main_window()
    end,

    ['r'] = function(_, helpers)
      helpers.refresh()
      vim.notify('[pkm] buffer panel refreshed', vim.log.levels.INFO)
    end,

    ['T'] = function(_, helpers)
      local mode = M.toggle_display_mode()
      helpers.refresh()
      require('pkm.views').refresh_sidebar_if_open()
      vim.notify('[pkm] note labels: ' .. mode, vim.log.levels.INFO)
    end,
  },
})

--- Return the current note label display mode.
---@return string  'filename' | 'title'
function M.get_display_mode()
  return _display_mode
end

--- Toggle between filename and title display. Returns the new mode.
---@return string
function M.toggle_display_mode()
  _display_mode = (_display_mode == 'filename') and 'title' or 'filename'
  return _display_mode
end

--- Refresh the buffer panel from outside this module.
function M.refresh_bufpanel()
  _bufpanel.refresh()
end

--- Toggle the persistent bottom buffer-list panel.
--- Opens at the bottom of the screen; closes if already open.
--- <CR> opens buffer in main window. d/D close it. w saves and closes.
--- r refreshes. q/<Esc> closes the panel.
function M.toggle_bufpanel()
  _bufpanel.toggle()
end

--- Return true if the buffer panel is currently open in the current tabpage.
---@return boolean
function M.is_bufpanel_open()
  return _bufpanel.is_open()
end

-- =============================================================================
-- SECTION: Tag panel
-- =============================================================================

local _tag_panel = panel.create({
  name          = 'tagpanel',
  split_cmd     = 'noautocmd botright split',
  focus_on_open = true,  -- unlike bufpanel: this is a modal-style picker
  resize = function(state, lines)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_height(state.win, math.min(#lines + 1, 12))
    end
  end,
  build_lines = function(state)
    local all_tags = require('pkm.citations').get_all_tags()
    local candidates

    if state.mode == 'remove' then
      candidates = state.buffer_tags or {}
    else
      local present = {}
      for _, t in ipairs(state.buffer_tags or {}) do present[t] = true end
      candidates = {}
      for _, t in ipairs(all_tags) do
        if not present[t] then candidates[#candidates + 1] = t end
      end
    end

    if state.filter and state.filter ~= '' then
      local needle = state.filter:lower()
      local filtered = {}
      for _, t in ipairs(candidates) do
        if t:lower():find(needle, 1, true) then filtered[#filtered + 1] = t end
      end
      candidates = filtered
    end

    local mode_label   = state.mode == 'remove' and 'Remove' or 'Add'
    local filter_label = (state.filter and state.filter ~= '')
      and ('  [filter: ' .. state.filter .. ']') or ''
    local lines = {
      string.format('  %s Tag  (%d)%s  <CR> select  / search  q close',
        mode_label, #candidates, filter_label),
    }
    local map = {}
    for _, t in ipairs(candidates) do
      lines[#lines + 1] = '  ' .. t
      map[#lines] = t
    end
    if #candidates == 0 then
      lines[#lines + 1] = (state.filter and state.filter ~= '')
        and '  (no tags match)' or '  (no tags available)'
    end
    return lines, map
  end,
  keymaps = {
    ['<CR>'] = function(state, helpers)
      local tag = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not tag then return end
      -- Close and restore focus to the original note window BEFORE calling
      -- into citations.add_tag/remove_tag — both operate on "current
      -- buffer" (buffer 0), which while this panel is still focused would
      -- resolve to the panel's own scratch buffer, not the note.
      -- restore_focus(state): close() wipes this panel's own buffer
      -- (bufhidden=wipe) synchronously, which clears the _tabs entry before
      -- close() returns — a bare restore_focus() would call get_tab() fresh
      -- and get a brand-new empty table, not the one holding prev_win.
      -- Passing the already-captured `state` sidesteps that.
      helpers.close()
      helpers.restore_focus(state)
      local citations = require('pkm.citations')
      if state.mode == 'remove' then
        citations.remove_tag(tag)
      else
        citations.add_tag(tag)
      end
    end,

    ['/'] = function(state, helpers)
      vim.fn.inputsave()
      local query = vim.fn.input('Filter tags: ', state.filter or '')
      vim.fn.inputrestore()
      state.filter = (query and query ~= '') and query or nil
      helpers.refresh()
    end,
  },
})

--- Open the tag panel to add or remove a tag on the current buffer.
--- Buffer-only mutation via citations.add_tag/remove_tag — no
--- index.invalidate (matches the existing buffer-only metadata contract;
--- the underlying citations functions are unchanged by this port).
---@param mode string 'add'|'remove'
function M.open_tag_panel(mode)
  local yaml_m = require('pkm.yaml')
  local lines  = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local fm     = yaml_m.parse_frontmatter(lines)
  if not fm then
    vim.notify('[pkm] no frontmatter found', vim.log.levels.WARN)
    return
  end

  local buffer_tags = {}
  if type(fm.tags) == 'table' then
    for _, t in ipairs(fm.tags) do buffer_tags[#buffer_tags + 1] = tostring(t) end
  end

  if mode == 'remove' and #buffer_tags == 0 then
    vim.notify('[pkm] no tags to remove', vim.log.levels.INFO)
    return
  end

  _tag_panel.open({ mode = mode, buffer_tags = buffer_tags, filter = '' })
end

-- =============================================================================
-- SECTION: Setup
-- =============================================================================
---@param user_config table Resolved PKM config from pkm.config.resolve()
function M.setup(user_config)
  config = user_config
  _display_mode = (user_config.display_mode == 'title') and 'title' or 'filename'

  -- Track "last opened" order for the buffer panel's MRU sort. Fires on
  -- every BufEnter into a real, listed buffer -- covers <CR> in the panel
  -- itself (nvim_set_current_buf fires BufEnter) and any other way a
  -- buffer gets focused, with no extra code needed at each call site.
  vim.api.nvim_create_autocmd('BufEnter', {
    callback = function(ev)
      if vim.bo[ev.buf].buflisted and vim.bo[ev.buf].buftype == '' then
        _open_counter = _open_counter + 1
        _open_order[ev.buf] = _open_counter
      end
    end,
  })

  -- Bufpanel statusline: set once per buffer creation, re-asserted on
  -- WinEnter/BufWinEnter — mirrors the pre-port behaviour exactly. Mirrors
  -- the FileType-hook pattern already established for netrw in keymaps.lua
  -- (PKMNetrwFixes), rather than needing panel.lua to expose an on-open hook.
  vim.api.nvim_create_autocmd('FileType', {
    pattern  = 'pkm-bufpanel',
    callback = function(ev)
      local function set_sl()
        vim.schedule(function()
          local win = vim.fn.bufwinid(ev.buf)
          if win ~= -1 then
            vim.api.nvim_set_option_value(
              'statusline',
              '  PKM Buffers  · CR open  · d close  · D force  · w save+close  · r refresh  · T title  · q close',
              { win = win })
          end
        end)
      end
      set_sl()
      vim.api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter' }, {
        buffer   = ev.buf,
        callback = set_sl,
      })
    end,
  })
end

-- =============================================================================
-- SECTION: Note browser
-- =============================================================================

--- Browse PKM notes (Telescope fallback). Prompts once for a filter expression,
--- evaluates it, and presents matching notes via vim.ui.select.
--- Note: vim.ui.select does not support live-as-you-type input; expression is
--- evaluated once. Bare text is treated as an any-field predicate.
---@param filter_expr string|nil  Optional pre-seeded expression
function M.browse(filter_expr)
  local filter = require('pkm.filter')
  local index  = require('pkm.index')

  local expr = filter_expr
  if not expr or expr == '' then
    vim.fn.inputsave()
    expr = vim.fn.input('Filter (blank = all): ')
    vim.fn.inputrestore()
  end

  local all_entries = index.get_all()
  local entries

  if expr and expr ~= '' then
    local tree, _ = filter.parse(expr)
    if not tree then
      tree = { type = 'PRED', field = 'any', value = expr }
    end
    entries = {}
    for _, e in ipairs(all_entries) do
      if filter.eval(tree, e) then entries[#entries + 1] = e end
    end
  else
    entries = all_entries
  end

  if #entries == 0 then
    vim.notify('[pkm] no notes match', vim.log.levels.INFO)
    return
  end

  table.sort(entries, function(a, b)
    local ta = _TYPE_ORDER[a.note_type] or 6
    local tb = _TYPE_ORDER[b.note_type] or 6
    if ta ~= tb then return ta < tb end
    return (a.title or ''):lower() < (b.title or ''):lower()
  end)

  vim.ui.select(entries, {
    prompt      = (expr and expr ~= '') and ('Browse: ' .. expr) or 'Browse Notes',
    format_item = function(e)
      return type_prefix(e.note_type) .. ' ' .. e.title .. '  (' .. e.filename .. ')'
    end,
  }, function(sel)
    if sel then vim.cmd('edit ' .. vim.fn.fnameescape(sel.path)) end
  end)
end

--- Scoped note browser over a pre-computed path list (Telescope fallback).
--- Presents notes via vim.ui.select sorted by type then title.
---@param title string
---@param paths string[]
function M.browse_paths(title, paths)
  local index = require('pkm.index')

  if #paths == 0 then
    vim.notify('[pkm] no notes to search', vim.log.levels.INFO)
    return
  end

  local entries = {}
  for _, path in ipairs(paths) do
    local e = index.get(path)
    if e then entries[#entries + 1] = e end
  end

  if #entries == 0 then
    vim.notify('[pkm] no indexed notes in selection', vim.log.levels.INFO)
    return
  end

  table.sort(entries, function(a, b)
    local ta = _TYPE_ORDER[a.note_type] or 6
    local tb = _TYPE_ORDER[b.note_type] or 6
    if ta ~= tb then return ta < tb end
    return (a.title or ''):lower() < (b.title or ''):lower()
  end)

  vim.ui.select(entries, {
    prompt      = title,
    format_item = function(e)
      return type_prefix(e.note_type) .. ' ' .. e.title .. '  (' .. e.filename .. ')'
    end,
  }, function(sel)
    if sel then vim.cmd('edit ' .. vim.fn.fnameescape(sel.path)) end
  end)
end

--- Show the n most recently modified notes (Telescope fallback).
---@param n integer|nil  Max results; defaults to 20
function M.browse_recent(n)
  n = tonumber(n) or 20
  local index = require('pkm.index')
  local entries = index.get_all()
  table.sort(entries, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
  if n > 0 and #entries > n then
    local sliced = {}
    for i = 1, n do sliced[i] = entries[i] end
    entries = sliced
  end
  if #entries == 0 then
    vim.notify('[pkm] no notes in index', vim.log.levels.INFO)
    return
  end
  vim.ui.select(entries, {
    prompt      = string.format('Recent (%d)', #entries),
    format_item = function(e)
      local dt = e.mtime and os.date('%Y-%m-%d', e.mtime) or '?'
      return type_prefix(e.note_type) .. ' ' .. e.title
           .. '  (' .. e.filename .. ')  ' .. dt
    end,
  }, function(sel)
    if sel then vim.cmd('edit ' .. vim.fn.fnameescape(sel.path)) end
  end)
end

--- Tag picker. On selection, opens browse() pre-filtered to tag:<selected>.
function M.browse_tags()
  local tags = require('pkm.citations').get_all_tags()

  if #tags == 0 then
    vim.notify('[pkm] no tags found', vim.log.levels.INFO)
    return
  end

  vim.ui.select(tags, {
    prompt = 'Browse by Tag',
    format_item = function(t) return t end,
  }, function(sel)
    if sel then M.browse('tag:' .. sel) end
  end)
end

-- =============================================================================
-- SECTION: Citation insertion fallback
-- =============================================================================
--- Context-aware fallback citation picker using vim.ui.select.
--- Items are pre-scored by view membership and shared tags.
--- '~ ' prefix marks contextually relevant items.
function M.insert_citation_ui()
  local citations = require('pkm.citations')
  local index     = require('pkm.index')
  local views     = require('pkm.views')

  local raw_items = citations.get_citable_items_for_picker()
  if #raw_items == 0 then
    vim.notify('PKM: No citable notes found.', vim.log.levels.INFO)
    return
  end

  -- Build scoring context
  local cur_path  = vim.fn.expand('%:p')
  local cur_entry = index.get(cur_path)
  local cur_tags  = {}
  if cur_entry and cur_entry.tags then
    for _, tag in ipairs(cur_entry.tags) do cur_tags[tag] = true end
  end

  local view_name  = views.get_last_view()
  local view_paths = {}
  if view_name then
    for _, p in ipairs(views.match_all(view_name)) do
      view_paths[utils.normalize(p)] = true
    end
  end

  -- Score and sort
  for _, item in ipairs(raw_items) do
    local score = view_paths[utils.normalize(item.path)] and 2 or 0
    local entry = index.get(item.path)
    if entry and entry.tags then
      for _, tag in ipairs(entry.tags) do
        if cur_tags[tag] then score = score + 1 end
      end
    end
    item.score = score
  end
  table.sort(raw_items, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.display < b.display
  end)

  local prompt = view_name
    and ('Insert Citation  ~ = contextual  [' .. view_name .. ']')
    or  'Insert Citation  ~ = contextual'

  vim.ui.select(raw_items, {
    prompt      = prompt,
    format_item = function(item)
      return (item.score > 0 and '~ ' or '  ') .. item.display
    end,
  }, function(selected)
    if selected then citations.complete_insertion(selected) end
  end)
end

-- =============================================================================
-- SECTION: Tag merging
-- =============================================================================
--- Interactive tag merge UI. Prompts for a target tag via vim.ui.select,
--- then accepts comma-separated source tags via input. Validates, confirms,
--- then delegates to citations.merge_tags(). Used as fallback when Telescope
--- is unavailable for PKMMergeTags.
function M.merge_tags_ui()
  local citations_mod = require('pkm.citations')
  local all_tags = citations_mod.get_all_tags()

  if #all_tags == 0 then
    vim.notify("PKM: No tags found.", vim.log.levels.INFO)
    return
  end

  -- Step 1: pick target from a list
  vim.ui.select(all_tags, {
    prompt = "Merge Tags — Pick TARGET tag (sources will be typed next)",
  }, function(target)
    if not target then return end

    -- Step 2: show available tags and let the user type sources
    local available = vim.tbl_filter(function(t) return t ~= target end, all_tags)
    local available_str = table.concat(available, "  |  ")

    vim.notify("Available tags:\n" .. available_str, vim.log.levels.INFO)

    vim.fn.inputsave()
    local raw = vim.fn.input(
      string.format("Sources to merge into '%s' (comma-separated): ", target)
    )
    vim.fn.inputrestore()

    if not raw or raw:match("^%s*$") then
      vim.notify("PKM: No sources entered. Merge cancelled.", vim.log.levels.INFO)
      return
    end

    -- Parse and validate
    local sources = {}
    local source_set = {}
    local invalid = {}
    local valid_set = {}
    for _, t in ipairs(available) do valid_set[t] = true end

    for entry in raw:gmatch("[^,]+") do
      local t = entry:match("^%s*(.-)%s*$")
      if t ~= "" then
        if valid_set[t] then
          if not source_set[t] then
            source_set[t] = true
            table.insert(sources, t)
          end
        else
          table.insert(invalid, t)
        end
      end
    end

    if #invalid > 0 then
      vim.notify(
        "PKM: Unknown tags (ignored): " .. table.concat(invalid, ", "),
        vim.log.levels.WARN
      )
    end

    if #sources == 0 then
      vim.notify("PKM: No valid source tags. Merge cancelled.", vim.log.levels.INFO)
      return
    end

    -- Confirm
    local src_str = table.concat(sources, ", ")
    vim.fn.inputsave()
    local answer = vim.fn.input(
      string.format("Merge [%s] → '%s'? (y/N): ", src_str, target), "n"
    )
    vim.fn.inputrestore()

    if answer:lower() ~= "y" then
      vim.notify("PKM: Tag merge cancelled.", vim.log.levels.INFO)
      return
    end

    local count = citations_mod.merge_tags(sources, target)
    vim.notify(
      string.format("PKM: Merged [%s] → '%s' in %d file(s).", src_str, target, count),
      vim.log.levels.INFO
    )
  end)
end

--- Show a statistics window with note counts per folder type.
--- Show note counts per folder via vim.notify.
--- Called by :PKMStats command.
function M.show_stats()
  local folders = {
    { label = "Consolidated", path = utils.join(config.root_path, config.folders.consolidated) },
    { label = "Journal",      path = utils.join(config.root_path, config.folders.journal) },
    { label = "Scratchpad",   path = utils.join(config.root_path, config.folders.scratchpad) },
  }

  local lines = { "PKM Statistics", string.rep("─", 30), "" }
  local total = 0

  for _, folder in ipairs(folders) do
    local files = vim.fn.glob(folder.path .. utils.sep .. "*.md", false, true)
    local count = type(files) == "table" and #files or 0
    total = total + count
    table.insert(lines, string.format("  %-16s %d notes", folder.label .. ":", count))
  end

  table.insert(lines, "")
  table.insert(lines, string.format("  %-16s %d notes", "Total:", total))
  table.insert(lines, "")
  table.insert(lines, "Root: " .. config.root_path)

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

-- Exposed for test/test_v160_p1.lua only; not part of the module's public API.
M._bufpanel  = _bufpanel
M._tag_panel = _tag_panel

return M
