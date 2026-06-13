-- =============================================================================
-- pkm.ui — Fallback UI components (no Telescope dependency)
-- =============================================================================
-- Dependencies : pkm.yaml, pkm.utils, pkm.citations (lazy), pkm.index (lazy),
--                pkm.views (lazy)
-- Consumed by  : pkm.commands, pkm.telescope (fallback)
--
-- Public API:
--   setup(user_config)       → Initialize with resolved PKM config
--   search_notes(query?)     → Full-text search with vim.ui.select results
--   browse_tags()            → Two-level tag → file picker
--   browse_paths(title, paths)   → fallback scoped picker over a pre-computed path list
--   browse(filter_expr?)     → Browse notes with optional filter expression
--   insert_citation_ui()     → Context-aware citation picker fallback (no Telescope);
--                               sorted by view membership and shared tags
--   merge_tags_ui()          → Interactive tag merge (fallback for PKMMergeTags)
--   show_stats()             → Show note counts via vim.notify
--   toggle_bufpanel()    → toggle the persistent bottom buffer-list panel
-- =============================================================================
local M = {}

local utils = require('pkm.utils')
local config = {}

local _bufpanel_win     = nil
local _bufpanel_buf     = nil
local _bufpanel_augroup = nil
local _bufpanel_map     = {}

local _TYPE_ORDER = { note = 1, agg = 2, bib = 3, journal = 4, scratch = 5, other = 6 }
local function type_prefix(note_type)
  local label = note_type or 'other'
  local width = 7
  local pad   = width - #label
  local lpad  = math.floor(pad / 2) + 1
  local rpad  = math.ceil(pad  / 2) + 1
  return '[' .. string.rep(' ', lpad) .. label .. string.rep(' ', rpad) .. ']'
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
    if bufnr ~= _bufpanel_buf
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == '' then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= '' then listed[#listed + 1] = bufnr end
    end
  end

  local lines   = { '  Buffers  (' .. #listed .. ')  <CR> open  d close  w save+close  q close panel' }
  local buf_map = {}

  for i, bufnr in ipairs(listed) do
    local name     = vim.api.nvim_buf_get_name(bufnr)
    local modified = vim.bo[bufnr].modified and ' [+]' or '    '
    local entry    = index.get(name)
    local display
    if entry then
      display = string.format('  %3d  %s %s%s',
        i, type_prefix(entry.note_type), entry.title, modified)
    else
      display = string.format('  %3d  %s %s%s',
        i, type_prefix('file'), vim.fn.fnamemodify(name, ':t'), modified)
    end
    lines[#lines + 1] = display
    buf_map[#lines]   = bufnr
  end

  if #listed == 0 then lines[#lines + 1] = '  (no open buffers)' end
  return lines, buf_map
end

--- Refresh buffer panel content in place.
local function bufpanel_refresh()
  if not _bufpanel_buf or not vim.api.nvim_buf_is_valid(_bufpanel_buf) then return end
  local lines, buf_map = bufpanel_build_lines()
  _bufpanel_map = buf_map
  vim.api.nvim_set_option_value('modifiable', true,  { buf = _bufpanel_buf })
  vim.api.nvim_buf_set_lines(_bufpanel_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = _bufpanel_buf })
  if _bufpanel_win and vim.api.nvim_win_is_valid(_bufpanel_win) then
    vim.api.nvim_win_set_height(_bufpanel_win, math.min(#lines + 1, 8))
  end
end

--- Ensure at least one main editing window exists alongside the buffer panel.
--- Called after bdelete operations to prevent the panel from becoming the sole
--- non-float window, which breaks Neovim's window layout.
local function ensure_main_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= _bufpanel_win
    and vim.api.nvim_win_get_config(win).relative == '' then
      return  -- a real editing window already exists
    end
  end
  -- Only the panel (or nothing) remains; open an editing window above it.
  if _bufpanel_win and vim.api.nvim_win_is_valid(_bufpanel_win) then
    local cur = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(_bufpanel_win)
    vim.cmd('noautocmd aboveleft new')
    if vim.api.nvim_win_is_valid(cur) then
      vim.api.nvim_set_current_win(cur)
    end
  end
end

--- Toggle the persistent bottom buffer-list panel.
--- Opens at the bottom of the screen; closes if already open.
--- <CR> opens buffer in main window. d/D close it. w saves and closes.
--- r refreshes. q/<Esc> closes the panel.
function M.toggle_bufpanel()
  if _bufpanel_win and not vim.api.nvim_win_is_valid(_bufpanel_win) then
    _bufpanel_win = nil; _bufpanel_buf = nil; _bufpanel_map = {}
    if _bufpanel_augroup then
      vim.api.nvim_del_augroup_by_id(_bufpanel_augroup)
      _bufpanel_augroup = nil
    end
  end

  if _bufpanel_win then
    vim.api.nvim_win_close(_bufpanel_win, true)
    return
  end

  local prev_win = vim.api.nvim_get_current_win()

  vim.cmd('noautocmd botright split')
  _bufpanel_win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  _bufpanel_buf = buf
  vim.api.nvim_win_set_buf(_bufpanel_win, buf)

  for opt, val in pairs({
    winfixheight = true, wrap = false,
    number = false, cursorline = true, signcolumn = 'no',
  }) do
    vim.api.nvim_set_option_value(opt, val, { win = _bufpanel_win })
  end

  for opt, val in pairs({
    bufhidden = 'wipe', buftype = 'nofile', swapfile = false,
  }) do
    vim.api.nvim_set_option_value(opt, val, { buf = buf })
  end

  local lines, buf_map = bufpanel_build_lines()
  _bufpanel_map = buf_map
  vim.api.nvim_set_option_value('modifiable', true,  { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_win_set_height(_bufpanel_win, math.min(#lines + 1, 8))

  _bufpanel_augroup = vim.api.nvim_create_augroup('PKMBufPanel', { clear = true })
  for _, event in ipairs({ 'BufAdd', 'BufDelete', 'BufWipeout', 'BufModifiedSet' }) do
    vim.api.nvim_create_autocmd(event, {
      group    = _bufpanel_augroup,
      callback = function() vim.schedule(bufpanel_refresh) end,
    })
  end

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer   = buf,
    once     = true,
    callback = function()
      _bufpanel_win = nil; _bufpanel_buf = nil; _bufpanel_map = {}
      if _bufpanel_augroup then
        vim.api.nvim_del_augroup_by_id(_bufpanel_augroup)
        _bufpanel_augroup = nil
      end
    end,
  })

  local ko = { noremap = true, silent = true, buffer = buf }

  vim.keymap.set('n', '<CR>', function()
    local bufnr = _bufpanel_map[vim.api.nvim_win_get_cursor(_bufpanel_win)[1]]
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
    local target
    local alt_id = vim.fn.win_getid(vim.fn.winnr('#'))
    if alt_id ~= 0 and alt_id ~= _bufpanel_win
    and vim.api.nvim_win_is_valid(alt_id)
    and vim.api.nvim_win_get_config(alt_id).relative == '' then
      target = alt_id
    end
    if not target then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= _bufpanel_win
        and vim.api.nvim_win_get_config(win).relative == '' then
          target = win; break
        end
      end
    end
    if target then
      vim.api.nvim_set_current_win(target)
      vim.api.nvim_set_current_buf(bufnr)
    end
  end, ko)

  vim.keymap.set('n', 'd', function()
    local bufnr = _bufpanel_map[vim.api.nvim_win_get_cursor(_bufpanel_win)[1]]
    if bufnr then
      local ok, err = pcall(vim.cmd, 'bdelete ' .. bufnr)
      if not ok then
        vim.notify('[pkm] ' .. (err or 'cannot close buffer'), vim.log.levels.WARN)
      else
        ensure_main_window()
      end
    end
  end, ko)

  vim.keymap.set('n', 'D', function()
    local bufnr = _bufpanel_map[vim.api.nvim_win_get_cursor(_bufpanel_win)[1]]
    if bufnr then
      local ok, err = pcall(vim.cmd, 'bdelete! ' .. bufnr)
      if not ok then
        vim.notify('[pkm] ' .. (err or 'cannot close buffer'), vim.log.levels.WARN)
      else
        ensure_main_window()
      end
    end
  end, ko)

  vim.keymap.set('n', 'w', function()
    local bufnr = _bufpanel_map[vim.api.nvim_win_get_cursor(_bufpanel_win)[1]]
    if not bufnr then return end
    local target
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= _bufpanel_win
      and vim.api.nvim_win_get_config(win).relative == '' then
        target = win; break
      end
    end
    if not target then
      vim.notify('[pkm] no window to write buffer in', vim.log.levels.WARN)
      return
    end
    local prev = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(target)
    vim.api.nvim_set_current_buf(bufnr)
    local ok, err = pcall(vim.cmd, 'write')
    if ok then
      pcall(vim.cmd, 'bdelete ' .. bufnr)
      ensure_main_window()
    else
      vim.notify('[pkm] write failed: ' .. (err or ''), vim.log.levels.ERROR)
    end
    vim.api.nvim_set_current_win(prev)
  end, ko)

  vim.keymap.set('n', 'r', function()
    bufpanel_refresh()
    vim.notify('[pkm] buffer panel refreshed', vim.log.levels.INFO)
  end, ko)

  local function close_panel()
    if _bufpanel_win and vim.api.nvim_win_is_valid(_bufpanel_win) then
      vim.api.nvim_win_close(_bufpanel_win, true)
    end
  end
  vim.keymap.set('n', 'q',     close_panel, ko)
  vim.keymap.set('n', '<Esc>', close_panel, ko)

  vim.api.nvim_set_current_win(prev_win)
end

-- =============================================================================
-- SECTION: Setup
-- =============================================================================
---@param user_config table Resolved PKM config from pkm.config.resolve()
function M.setup(user_config)
  config = user_config
end

-- =============================================================================
-- SECTION: Search
-- =============================================================================
--- Full-text search across all three PKM folders.
--- Prompts for query if not provided. Opens result in editor and jumps to
--- first matching line. Uses vim.ui.select for result display.
---@param query string|nil Search string; prompts if nil or empty
function M.search_notes(query)
  -- Collect all markdown files
  local search_paths = {
    utils.join(config.root_path, config.folders.consolidated),
    utils.join(config.root_path, config.folders.journal),
    utils.join(config.root_path, config.folders.scratchpad),
  }
  
  local results = {}
  
  -- If no query provided, prompt for it
  if not query or query == "" then
    vim.fn.inputsave()
    query = vim.fn.input("Search: ")
    vim.fn.inputrestore()
    
    if not query or query == "" then
      vim.notify("Search cancelled", vim.log.levels.INFO)
      return
    end
  end
  
  local query_lower = query:lower()
  
  for _, search_path in ipairs(search_paths) do
    local files = vim.fn.glob(search_path .. utils.sep .. "*.md", false, true)
    
    for _, file in ipairs(files) do
      local content = vim.fn.readfile(file)
      local matches = {}
      
      for line_num, line in ipairs(content) do
        if line:lower():find(query_lower, 1, true) then
          table.insert(matches, {
            line_num = line_num,
            text = line:sub(1, 100), -- Truncate long lines
          })
        end
      end
      
      if #matches > 0 then
        table.insert(results, {
          path = file,
          filename = vim.fn.fnamemodify(file, ":t"),
          matches = matches,
          match_count = #matches,
        })
      end
    end
  end
  
  if #results == 0 then
    vim.notify("No results found for: " .. query, vim.log.levels.INFO)
    return
  end
  
  -- Display results
  local display_items = {}
  for _, result in ipairs(results) do
    local display = string.format("%s (%d matches)", result.filename, result.match_count)
    table.insert(display_items, {
      display = display,
      result = result,
    })
  end
  
  vim.ui.select(display_items, {
    prompt = string.format("Search results for '%s':", query),
    format_item = function(item) return item.display end,
  }, function(selected)
    if selected then
      vim.cmd("edit " .. vim.fn.fnameescape(selected.result.path))
      
      -- Jump to first match
      if #selected.result.matches > 0 then
        vim.api.nvim_win_set_cursor(0, {selected.result.matches[1].line_num, 0})
      end
    end
  end)
end

-- =============================================================================
-- SECTION: Note browser
-- =============================================================================

--- Browse PKM notes with optional filter expression. Fallback for PKMBrowse
--- when Telescope is unavailable. Uses vim.ui.select.
---@param filter_expr string|nil
function M.browse(filter_expr)
  local filter = require('pkm.filter')
  local index  = require('pkm.index')

  local all_entries = index.get_all()
  local entries

  if filter_expr and filter_expr ~= '' then
    local tree, err = filter.parse(filter_expr)
    if not tree then
      vim.notify('[pkm] invalid filter: ' .. err, vim.log.levels.ERROR)
      return
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
    prompt = filter_expr and ('Browse: ' .. filter_expr) or 'Browse Notes',
    format_item = function(e)
      return type_prefix(e.note_type) .. ' ' .. e.title .. '  (' .. e.filename .. ')'
    end,
  }, function(sel)
    if sel then vim.cmd('edit ' .. vim.fn.fnameescape(sel.path)) end
  end)
end

--- Fallback scoped picker over a pre-supplied path list. Used when Telescope
--- is unavailable. Sorts by type then title internally.
---@param title string
---@param paths string[]
function M.browse_paths(title, paths)
  local index = require('pkm.index')

  if #paths == 0 then
    vim.notify('[pkm] no notes to search', vim.log.levels.INFO)
    return
  end

  local sorted = vim.list_extend({}, paths)
  table.sort(sorted, function(a, b)
    local ea = index.get(a)
    local eb = index.get(b)
    local ta = ea and (_TYPE_ORDER[ea.note_type] or 6) or 6
    local tb = eb and (_TYPE_ORDER[eb.note_type] or 6) or 6
    if ta ~= tb then return ta < tb end
    return (ea and ea.title or ''):lower() < (eb and eb.title or ''):lower()
  end)

  local items = {}
  for _, path in ipairs(sorted) do
    local e         = index.get(path)
    local note_type = e and e.note_type or 'other'
    local ttl       = e and e.title or vim.fn.fnamemodify(path, ':t:r')
    items[#items + 1] = {
      path    = path,
      display = type_prefix(note_type) .. ' ' .. ttl,
    }
  end

  vim.ui.select(items, {
    prompt      = title,
    format_item = function(item) return item.display end,
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
