-- =============================================================================
-- pkm.ui — Fallback UI components (no Telescope dependency)
-- =============================================================================
-- Dependencies : pkm.yaml, pkm.utils, pkm.citations (lazy), pkm.index (lazy),
--                pkm.views (lazy)
-- Consumed by  : pkm.commands, pkm.telescope (fallback)
--
-- Public API:
--   setup(user_config)       → Initialize with resolved PKM config
--   browse_tags()            → Two-level tag → file picker
--   browse(filter_expr?)     → Prompt for filter expression, eval, vim.ui.select results
--   browse_paths(title, paths) → Show scoped path list via vim.ui.select (sorted)
--   browse_recent(n?)         → n most-recently-modified notes via vim.ui.select
--   insert_citation_ui()     → Context-aware citation picker fallback (no Telescope);
--                               sorted by view membership and shared tags
--   merge_tags_ui()          → Interactive tag merge (fallback for PKMMergeTags)
--   show_stats()             → Show note counts via vim.notify
--   get_display_mode()    → 'filename' | 'title'
--   toggle_display_mode() → toggle and return new mode
--   refresh_bufpanel()    → refresh panel from outside
--   toggle_bufpanel()  → toggle the persistent bottom buffer-list panel (per-tabpage)
--   is_bufpanel_open()   → boolean, whether buffer panel is open in current tabpage
-- =============================================================================
local M = {}

local utils = require('pkm.utils')
local config = {}
local _display_mode = 'filename'  -- 'filename' | 'title'

-- Per-tabpage bufpanel state. Keyed by nvim_get_current_tabpage().
local _tabs = {}

local function get_tab()
  local id = vim.api.nvim_get_current_tabpage()
  if not _tabs[id] then
    _tabs[id] = { win = nil, buf = nil, augroup = nil, map = {} }
  end
  return _tabs[id]
end

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
---@return string[], table  lines, buf_map (1-based line → bufnr)
local function bufpanel_build_lines()
  local index  = require('pkm.index')
  local listed = {}

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= get_tab().buf
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ''
    and vim.bo[bufnr].filetype ~= 'netrw'
    and vim.fn.isdirectory(vim.api.nvim_buf_get_name(bufnr)) == 0 then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= '' then listed[#listed + 1] = bufnr end
    end
  end

  -- Sort by mtime — most recently modified buffer first.
  table.sort(listed, function(a, b)
    local na = vim.api.nvim_buf_get_name(a)
    local nb = vim.api.nvim_buf_get_name(b)
    local ea = index.get(na)
    local eb = index.get(nb)
    local ma = ea and ea.mtime or vim.fn.getftime(na)
    local mb = eb and eb.mtime or vim.fn.getftime(nb)
    return ma > mb
  end)

  local lines   = { '  Buffers  (' .. #listed .. ')  <CR> open  d close  D force  w save+close  r refresh  T title  q close' }
  local buf_map = {}

  local win_labels = {}
  local win_num    = 0
  local _PANEL_FT  = { ['pkm-sidebar'] = true, ['pkm-bufpanel'] = true, ['netrw'] = true }
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == '' then
      if not _PANEL_FT[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
        win_num = win_num + 1
        local wbuf = vim.api.nvim_win_get_buf(win)
        if not win_labels[wbuf] then win_labels[wbuf] = {} end
        table.insert(win_labels[wbuf], '<- w' .. win_num)
      end
    end
  end

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

--- Refresh buffer panel content in place.
local function bufpanel_refresh()
  local t = get_tab()
  if not t.buf or not vim.api.nvim_buf_is_valid(t.buf) then return end
  local lines, buf_map = bufpanel_build_lines()
  t.map = buf_map
  vim.api.nvim_set_option_value('modifiable', true,  { buf = t.buf })
  vim.api.nvim_buf_set_lines(t.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = t.buf })
  if t.win and vim.api.nvim_win_is_valid(t.win) then
    vim.api.nvim_win_set_height(t.win, math.min(#lines + 1, 8))
  end
end

--- Ensure at least one main editing window exists alongside the buffer panel.
--- Called after bdelete operations to prevent the panel from becoming the sole
--- non-float window, which breaks Neovim's window layout.
local function ensure_main_window()
  local t = get_tab()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= t.win
    and vim.api.nvim_win_get_config(win).relative == '' then
      return
    end
  end
  if t.win and vim.api.nvim_win_is_valid(t.win) then
    local cur = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(t.win)
    vim.cmd('noautocmd aboveleft new')
    vim.bo.bufhidden = 'wipe'
    if vim.api.nvim_win_is_valid(cur) then
      vim.api.nvim_set_current_win(cur)
    end
  end
end

--- Switch all non-panel, non-float windows in the current tabpage that
--- are showing bufnr away from it before a bdelete call.
--- Prefers the window's alternate buffer; falls back to any other listed
--- buffer; last resort is a new empty buffer. Prevents bdelete from
--- closing windows unintentionally.
local function detach_buf_from_wins(bufnr)
  local ct = get_tab()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= ct.win
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
  bufpanel_refresh()
end

--- Toggle the persistent bottom buffer-list panel.
--- Opens at the bottom of the screen; closes if already open.
--- <CR> opens buffer in main window. d/D close it. w saves and closes.
--- r refreshes. q/<Esc> closes the panel.
function M.toggle_bufpanel()
  local t = get_tab()
  local my_tab_id = vim.api.nvim_get_current_tabpage()

  if t.win and not vim.api.nvim_win_is_valid(t.win) then
    if t.augroup then pcall(vim.api.nvim_del_augroup_by_id, t.augroup) end
    _tabs[my_tab_id] = nil
    t = get_tab()
  end

  if t.win then
    vim.api.nvim_win_close(t.win, true)
    return
  end

  local prev_win = vim.api.nvim_get_current_win()

  vim.cmd('noautocmd botright split')
  t.win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  t.buf = buf
  vim.api.nvim_win_set_buf(t.win, buf)

  for opt, val in pairs({
    winfixbuf = true, winfixheight = true, wrap = false,
    number = false, cursorline = true, signcolumn = 'no',
  }) do
    vim.api.nvim_set_option_value(opt, val, { win = t.win })
  end
  vim.api.nvim_set_option_value('colorcolumn', '', { win = t.win })  -- ← add

  for opt, val in pairs({
    bufhidden = 'wipe', buftype = 'nofile', swapfile = false,
  }) do
    vim.api.nvim_set_option_value(opt, val, { buf = buf })
  end

  vim.api.nvim_set_option_value('filetype', 'pkm-bufpanel', { buf = buf })

  local function refresh_bufpanel_sl()
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(t.win) then
        vim.api.nvim_set_option_value(
          'statusline',
          '  PKM Buffers  · CR open  · d close  · D force  · w save+close  · r refresh  · T title  · q close',
          { win = t.win })
      end
    end)
  end
  refresh_bufpanel_sl()
  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter' }, {
    buffer   = buf,
    callback = refresh_bufpanel_sl,
  })

  local lines, buf_map = bufpanel_build_lines()
  t.map = buf_map
  vim.api.nvim_set_option_value('modifiable', true,  { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_win_set_height(t.win, math.min(#lines + 1, 8))

  t.augroup = vim.api.nvim_create_augroup(
    'PKMBufPanel_' .. my_tab_id, { clear = true })
  for _, event in ipairs({ 'BufAdd', 'BufDelete', 'BufWipeout', 'BufModifiedSet', 'BufEnter' }) do
    vim.api.nvim_create_autocmd(event, {
      group    = t.augroup,
      callback = function() vim.schedule(bufpanel_refresh) end,
    })
  end

  -- Safety net: ensure_main_window() already prevents the panel from
  -- becoming the sole window after the panel's own d/D/w close a buffer.
  -- This generalizes that to every path — closing the last editing window
  -- via plain :q, :bd, <C-w>c, etc. typed directly in it, with the panel
  -- left open, was never covered by those three keymaps and is a
  -- pre-existing gap, not something introduced by recent changes.
  vim.api.nvim_create_autocmd('WinClosed', {
    group    = t.augroup,
    callback = function()
      vim.schedule(function()
        if t.win and vim.api.nvim_win_is_valid(t.win) then
          ensure_main_window()
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer   = buf,
    once     = true,
    callback = function()
      local old_t = _tabs[my_tab_id]
      if old_t and old_t.augroup then
        pcall(vim.api.nvim_del_augroup_by_id, old_t.augroup)
      end
      _tabs[my_tab_id] = nil
    end,
  })

  local ko = { noremap = true, silent = true, buffer = buf }

  vim.keymap.set('n', '<CR>', function()
    local ct    = get_tab()
    local bufnr = ct.map[vim.api.nvim_win_get_cursor(ct.win)[1]]
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

    local _PANELS = { ['pkm-sidebar'] = true, ['pkm-bufpanel'] = true, ['netrw'] = true }
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
      vim.api.nvim_set_current_buf(bufnr)
    else
      vim.api.nvim_set_current_win(ct.win)
      vim.cmd('aboveleft new')
      vim.bo.bufhidden = 'wipe'
      vim.api.nvim_set_current_buf(bufnr)
    end
  end, ko)

  vim.keymap.set('n', 'd', function()
    local ct    = get_tab()
    local bufnr = ct.map[vim.api.nvim_win_get_cursor(ct.win)[1]]
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

    if vim.bo[bufnr].modified then
      local name  = vim.api.nvim_buf_get_name(bufnr)
      local label = name ~= '' and vim.fn.fnamemodify(name, ':t') or '[No Name]'
      local choice = vim.fn.confirm(
        string.format("Save changes to '%s' before closing?", label),
        '&Yes\n&No\n&Cancel', 1)
      if choice ~= 1 and choice ~= 2 then
        -- Cancel, <Esc>, or dialog dismissed: leave the buffer and its
        -- window exactly as they were.
        return
      end
      if choice == 1 then
        local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd('write') end)
        if not ok then
          vim.notify('[pkm] write failed: ' .. (err or ''), vim.log.levels.ERROR)
          return
        end
      end
      -- choice == 2 (No): fall through and force-close below, discarding
      -- the unsaved changes.
    end

    -- Only detach the buffer from its window now that we know the close
    -- will actually succeed — previously this ran unconditionally before
    -- attempting bdelete, so a modified buffer's window got switched away
    -- even when the subsequent bdelete then failed, forcing a trip back
    -- to find the buffer just to save it.
    detach_buf_from_wins(bufnr)
    local force = vim.bo[bufnr].modified and '!' or ''
    local ok, err = pcall(vim.cmd, 'bdelete' .. force .. ' ' .. bufnr)
    if not ok then
      vim.notify('[pkm] ' .. (err or 'cannot close buffer'), vim.log.levels.WARN)
    else
      ensure_main_window()
    end
  end, ko)

  vim.keymap.set('n', 'D', function()
    local ct    = get_tab()
    local bufnr = ct.map[vim.api.nvim_win_get_cursor(ct.win)[1]]
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
    detach_buf_from_wins(bufnr)
    local ok, err = pcall(vim.cmd, 'bdelete! ' .. bufnr)
    if not ok then
      vim.notify('[pkm] ' .. (err or 'cannot close buffer'), vim.log.levels.WARN)
    else
      ensure_main_window()
    end
  end, ko)

  vim.keymap.set('n', 'w', function()
    local ct    = get_tab()
    local bufnr = ct.map[vim.api.nvim_win_get_cursor(ct.win)[1]]
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
    local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
      vim.cmd('write')
    end)
    if not ok then
      vim.notify('[pkm] write failed: ' .. (err or ''), vim.log.levels.ERROR)
      return
    end
    detach_buf_from_wins(bufnr)
    pcall(vim.cmd, 'bdelete ' .. bufnr)
    ensure_main_window()
  end, ko)

  vim.keymap.set('n', 'r', function()
    bufpanel_refresh()
    vim.notify('[pkm] buffer panel refreshed', vim.log.levels.INFO)
  end, ko)

  vim.keymap.set('n', 'T', function()
    local mode = M.toggle_display_mode()
    bufpanel_refresh()
    require('pkm.views').refresh_sidebar_if_open()
    vim.notify('[pkm] note labels: ' .. mode, vim.log.levels.INFO)
  end, ko)

  local function close_panel()
    local ct = get_tab()
    if ct.win and vim.api.nvim_win_is_valid(ct.win) then
      vim.api.nvim_win_close(ct.win, true)
    end
  end
  vim.keymap.set('n', 'q',     close_panel, ko)
  vim.keymap.set('n', '<Esc>', close_panel, ko)

  vim.api.nvim_set_current_win(prev_win)
end

--- Return true if the buffer panel is currently open in the current tabpage.
---@return boolean
function M.is_bufpanel_open()
  local t = get_tab()
  return t.win ~= nil and vim.api.nvim_win_is_valid(t.win)
end

-- =============================================================================
-- SECTION: Setup
-- =============================================================================
---@param user_config table Resolved PKM config from pkm.config.resolve()
function M.setup(user_config)
  config = user_config
  _display_mode = (user_config.display_mode == 'title') and 'title' or 'filename'
  local augroup = vim.api.nvim_create_augroup('PKMUITabs', { clear = true })
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

return M
