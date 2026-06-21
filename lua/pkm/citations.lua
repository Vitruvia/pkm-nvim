-- =============================================================================
-- pkm.citations — Bidirectional citation engine
-- =============================================================================
-- Dependencies : pkm.yaml, pkm.utils
-- Consumed by  : pkm.notes, pkm.journal, pkm.telescope, pkm.ui, pkm.commands
--
-- Public API:
--   add_tag(tag?)    → append tag to current buffer frontmatter (buffer-only)
--   remove_tag(tag?) → remove tag from current buffer frontmatter (buffer-only; picker if no arg)
--   setup(config)                    → Initialize with resolved PKM config
--   parse_citation(text)             → (type, short_id) from citation string
--   get_note_type_and_id(filepath)   → (item_type, identifier) from file path
--   get_note_title(filepath)         → string title from frontmatter or filename
--   get_all_tags()                   → string[] sorted list of all tags in wiki
--   get_citable_items_map()          → table<id, item> all citable notes (LibUV)
--   get_citable_items_for_picker()   → item[] formatted list for pickers
--   get_citable_items_list           → alias for get_citable_items_for_picker
--   complete_insertion(selected)     → insert citation at cursor, trigger sync
--   update_references(target_file?)  → sync cites/cited_by for one file
--   goto_citation()                  → jump to note under cursor
--   update_references_on_rename(old, new, title?) → propagate rename/deletion across wiki
--   cleanup_deleted_note(filepath)   → remove all references to a deleted note
--   merge_tags(source_tags, target_tag) → rewrite tags across all notes
-- =============================================================================
local M = {}

local utils = require('pkm.utils')
local config = {}
local yaml = nil

-- =============================================================================
-- SECTION: Setup
-- =============================================================================
---@param user_config table Resolved PKM config from pkm.config.resolve()
function M.setup(user_config)
  config = user_config
  yaml = require('pkm.yaml')
end

-- =============================================================================
-- SECTION: Identifier and metadata helpers
-- =============================================================================
--- Parse a citation token from document text.
--- Matches patterns like note[0042], bib[0005], journal[2024-01-15_...].
---@param text string A single citation token
---@return string|nil cite_type  e.g. "note", "bib", "journal", "scratch"
---@return string|nil short_id   e.g. "0042", "0005"
function M.parse_citation(text) 
  return text:match("(%w+)%[([%w%-_]+)%]") 
end

--- Extract item type and full identifier from a note file path.
--- Consolidated: returns ("note"|"bib", "note-0042"|"bib-0005")
--- Journal/scratch: returns ("journal"|"scratch", timestamp-string)
---@param filepath string Absolute path to note file
---@return string|nil item_type
---@return string|nil identifier
function M.get_note_type_and_id(filepath)
  local filename = vim.fn.fnamemodify(filepath, ":t:r")
  local number, note_type = filename:match("^(%d+)_([a-z]+)_")
  if number and note_type then
    local item_type = (note_type == "bib") and "bib" or "note"
    return item_type, item_type .. "-" .. number
  end
  if filename:match("^journal_") then
    return "journal", filename:match("^journal_(.+)$")
  elseif filename:match("^scratch_") then
    return "scratch", filename:match("^scratch_(.+)$")
  end
  return nil, nil
end

--- Read the title of a note from its YAML frontmatter.
--- Falls back to a humanized filename if frontmatter is absent or title is empty.
---@param filepath string Absolute path to note file
---@return string title
function M.get_note_title(filepath)
  local ok, content = pcall(vim.fn.readfile, filepath)
  if not ok or not content then
    return vim.fn.fnamemodify(filepath, ":t:r"):gsub("_", " ")
  end
  
  local fm, _ = yaml.parse_frontmatter(content)
  return (fm and fm.title and fm.title ~= "") 
    and fm.title 
    or vim.fn.fnamemodify(filepath, ":t:r"):gsub("_", " ")
end

-- =============================================================================
-- SECTION: Tag indexing
-- =============================================================================
local function get_file_tags(filepath)
  local content = vim.fn.readfile(filepath)
  local fm, _ = yaml.parse_frontmatter(content)
  local tags = {}
  
  if fm and fm.tags then
    if type(fm.tags) == "table" then
      tags = fm.tags
    elseif type(fm.tags) == "string" then
      local clean = fm.tags:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
      tags = { clean }
    end
  end
  return tags
end

--- Collect all unique tags across every note in the wiki (all three folders).
--- Returns a sorted list with duplicates removed.
---@return string[] Sorted array of tag strings
function M.get_all_tags()
  local all_tags = {}
  local search_paths = {
    config.folders.consolidated, 
    config.folders.journal, 
    config.folders.scratchpad
  }

  for _, folder in ipairs(search_paths) do
    if folder then
        local search_path = utils.join(config.root_path, folder)
        local files = vim.fn.glob(search_path .. "/*.md", false, true)
        if type(files) ~= "table" then files = {} end
        
        for _, file in ipairs(files) do
            local tags = get_file_tags(file)
            for _, t in ipairs(tags) do
                if t and t ~= "" then all_tags[t] = true end
            end
        end
    end
  end
  
  local sorted_tags = vim.tbl_keys(all_tags)
  table.sort(sorted_tags)
  return sorted_tags
end

-- =============================================================================
-- SECTION: Tag editing (buffer-only)
-- =============================================================================

--- Append a tag to the current buffer's frontmatter tags list.
--- Buffer-only — no disk write. Silently skips if the tag is already present.
--- Must NOT call index.invalidate: no disk write; re-indexed on user save.
---@param tag string|nil  Tag to add; prompts if nil or empty
function M.add_tag(tag)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local fm, content_start = yaml.parse_frontmatter(lines)
  if not fm then
    vim.notify('[pkm] no frontmatter found', vim.log.levels.WARN)
    return
  end

  if not tag or tag:match('^%s*$') then
    vim.fn.inputsave()
    tag = vim.fn.input('Add tag: ')
    vim.fn.inputrestore()
    if not tag or tag:match('^%s*$') then return end
  end

  tag = tag:lower():match('^%s*(.-)%s*$')

  if type(fm.tags) ~= 'table' then fm.tags = {} end
  for _, t in ipairs(fm.tags) do
    if tostring(t):lower() == tag then
      vim.notify('[pkm] tag already present: ' .. tag, vim.log.levels.INFO)
      return
    end
  end

  fm.tags[#fm.tags + 1] = tag
  yaml.save_frontmatter(fm, content_start)   -- Case A: buffer-only
  require('pkm.syntax').refresh_fold(vim.api.nvim_get_current_buf())
  vim.notify('[pkm] tag added: ' .. tag .. ' — save to persist', vim.log.levels.INFO)
end

--- Remove a tag from the current buffer's frontmatter tags list.
--- Buffer-only — no disk write. Presents a picker when no tag argument is given.
--- Must NOT call index.invalidate: no disk write; re-indexed on user save.
---@param tag string|nil  Tag to remove; picker if nil or empty
function M.remove_tag(tag)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local fm, content_start = yaml.parse_frontmatter(lines)
  if not fm then
    vim.notify('[pkm] no frontmatter found', vim.log.levels.WARN)
    return
  end

  if type(fm.tags) ~= 'table' or #fm.tags == 0 then
    vim.notify('[pkm] no tags to remove', vim.log.levels.INFO)
    return
  end

  local function do_remove(t)
    t = tostring(t):lower()
    local new_tags, found = {}, false
    for _, existing in ipairs(fm.tags) do
      if tostring(existing):lower() == t then
        found = true
      else
        new_tags[#new_tags + 1] = existing
      end
    end
    if not found then
      vim.notify('[pkm] tag not found: ' .. t, vim.log.levels.WARN)
      return
    end
    fm.tags = new_tags
    yaml.save_frontmatter(fm, content_start)  -- Case A: buffer-only
    require('pkm.syntax').refresh_fold(vim.api.nvim_get_current_buf())
    vim.notify('[pkm] tag removed: ' .. t .. ' — save to persist', vim.log.levels.INFO)
  end

  if tag and not tag:match('^%s*$') then
    do_remove(tag:match('^%s*(.-)%s*$'))
  else
    vim.ui.select(fm.tags, {
      prompt      = 'Remove tag:',
      format_item = function(t) return tostring(t) end,
    }, function(sel)
      if sel then do_remove(sel) end
    end)
  end
end

-- =============================================================================
-- SECTION: Citable item scanning
-- =============================================================================
--- Build an index of all citable notes in the wiki.
--- Uses LibUV (vim.uv) for native UTF-8 filename support.
--- Scans consolidated, journal, and scratchpad folders.
---@return table<string, {path:string, basename:string, type:string, title:string}>
function M.get_citable_items_map()
  local items_map = {}
  local search_paths = {
    config.folders.consolidated, 
    config.folders.journal, 
    config.folders.scratchpad
  }
  local uv = vim.uv or vim.loop
  
  for _, folder in ipairs(search_paths) do
    if folder then
        local search_path = utils.join(config.root_path, folder)
        local req = uv.fs_scandir(search_path)
        
        if req then
          while true do
            local name, _ = uv.fs_scandir_next(req)
            if not name then break end
            
            if name:match("%.md$") then
              local file = utils.join(search_path, name)
              local item_type, id = M.get_note_type_and_id(file)
              if item_type and id then
                items_map[id] = {
                  path = file,
                  basename = vim.fn.fnamemodify(file, ":t:r"),
                  type = item_type,
                  title = M.get_note_title(file)
                }
              end
            end
          end
        end
    end
  end
  
  return items_map
end

--- Return a formatted list of all citable items suitable for a UI picker.
--- Each entry contains display string, type, identifier, short_id, and path.
---@return {type:string, identifier:string, short_id:string, display:string, path:string}[]
function M.get_citable_items_for_picker()
  local items = {}
  local all_items_map = M.get_citable_items_map()
  
  for id, data in pairs(all_items_map) do
    local short_id = id:match("note%-(%d+)") 
    or id:match("bib%-(%d+)") 
    or id
    
    table.insert(items, {
      type = data.type,
      identifier = id,
      short_id = short_id,
      display = string.format("[%s %s] %s", data.type, short_id, data.title),
      path = data.path
    })
  end
  
  table.sort(items, function(a, b) return a.display < b.display end)
  return items
end

-- Compatibility alias for Telescope
M.get_citable_items_list = M.get_citable_items_for_picker

-- =============================================================================
-- SECTION: cited_by structure management
-- =============================================================================
--- Initialize or migrate cited_by to new grouped structure
local function ensure_grouped_cited_by(frontmatter)
  if not frontmatter.cited_by then
    frontmatter.cited_by = {notes = {}, bib = {}, journal = {}, scratch = {}}
    return false
  end
  if frontmatter.cited_by.notes or frontmatter.cited_by.bib then
    frontmatter.cited_by.notes   = frontmatter.cited_by.notes   or {}
    frontmatter.cited_by.bib     = frontmatter.cited_by.bib     or {}
    frontmatter.cited_by.journal = frontmatter.cited_by.journal or {}
    frontmatter.cited_by.scratch = frontmatter.cited_by.scratch or {}  -- ADD
    return false
  end
  -- migration from flat format (same as before, just add scratch bucket)
  local old_array = frontmatter.cited_by
  local new_structure = {notes = {}, bib = {}, journal = {}, scratch = {}}
  if type(old_array) == "table" then
    for _, entry in ipairs(old_array) do
      if type(entry) == "table" and entry.identifier then
        local clean_entry = {identifier = entry.identifier, title = entry.title, link = entry.link}
        if entry.type == "bib" then
          table.insert(new_structure.bib, clean_entry)
        elseif entry.type == "journal" then
          table.insert(new_structure.journal, clean_entry)
        elseif entry.type == "scratch" then
          table.insert(new_structure.scratch, clean_entry)
        else
          table.insert(new_structure.notes, clean_entry)
        end
      end
    end
  end
  frontmatter.cited_by = new_structure
  return true
end

--- Adds or removes a backlink from a target file.
--- If the target is open in a modified buffer, applies the change in-buffer
--- only (no disk write) to avoid discarding the user's unsaved edits.
--- If the target is unmodified or not open, writes disk and refreshes.
local function manage_backlink(citing_path, target_path, action)
  local citing_type, citing_id = M.get_note_type_and_id(citing_path)
  if not citing_type or not citing_id then return end

  -- Locate any open buffer for the target.
  local norm_target  = utils.normalize(target_path)
  local target_bufnr = nil
  local buf_modified = false
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local bname = utils.normalize(vim.api.nvim_buf_get_name(bufnr))
      if bname == norm_target then
        target_bufnr = bufnr
        buf_modified = vim.bo[bufnr].modified
        break
      end
    end
  end

  -- Read from the appropriate source.
  -- A modified buffer may have frontmatter that differs from disk; reading
  -- from the buffer lets us compose with (not overwrite) the user's edits.
  local content
  if target_bufnr and buf_modified then
    content = vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
  else
    local ok
    ok, content = pcall(vim.fn.readfile, target_path)
    if not ok or not content then return end
  end

  local fm, content_start = yaml.parse_frontmatter(content)
  if not fm or fm.type == "agg" then return end

  local migrated = ensure_grouped_cited_by(fm)

  local group
  if     citing_type == "bib"     then group = "bib"
  elseif citing_type == "journal" then group = "journal"
  elseif citing_type == "scratch" then group = "scratch"
  else                                  group = "notes"
  end

  local found_index = nil
  if fm.cited_by and fm.cited_by[group] then
    for i, backlink in ipairs(fm.cited_by[group]) do
      if backlink.identifier == citing_id then
        found_index = i
        break
      end
    end
  end

  local modified = migrated

  if action == "add" and not found_index then
    if not fm.cited_by[group] then fm.cited_by[group] = {} end
    table.insert(fm.cited_by[group], {
      identifier = citing_id,
      title      = M.get_note_title(citing_path),
      link       = "[[" .. vim.fn.fnamemodify(citing_path, ":t:r") .. "]]",
    })
    modified = true
  elseif action == "remove" and found_index then
    table.remove(fm.cited_by[group], found_index)
    modified = true
  end

  if not modified then return end

  local sort_fn = function(a, b) return (a.identifier or "") < (b.identifier or "") end
  for _, g in ipairs({ "notes", "bib", "journal", "scratch" }) do
    if fm.cited_by[g] then table.sort(fm.cited_by[g], sort_fn) end
  end

  if target_bufnr and buf_modified then
    -- Target is open with unsaved edits.
    -- Apply the cited_by change directly into the buffer; never write disk,
    -- never reload, never set modified=false — all three would discard edits.
    -- The user's next :w persists both their edits and this change.
    -- index.invalidate is intentionally skipped: no disk write occurred;
    -- BufWritePost re-indexes on the user's save.
    local fm_lines    = yaml.generate_yaml(fm)
    local new_content = { "---" }
    for _, line in ipairs(fm_lines)       do new_content[#new_content + 1] = line end
    new_content[#new_content + 1] = "---"
    for i = content_start, #content       do new_content[#new_content + 1] = content[i] end
    vim.api.nvim_buf_call(target_bufnr, function()
      -- Merge into target_bufnr's own undo history rather than creating a
      -- separate step in a buffer the user may not have focused — this is
      -- the system reacting to a citation change elsewhere, not user input.
      pcall(vim.cmd, 'undojoin')
      pcall(vim.api.nvim_buf_set_lines, target_bufnr, 0, -1, false, new_content)
    end)
    require('pkm.syntax').refresh_fold(target_bufnr)
  else
    -- Target not open, or open but unmodified: write to disk.
    yaml.save_frontmatter(fm, content_start, target_path)
    require('pkm.index').invalidate(target_path)

    -- Reload the buffer in-place if it is loaded and unmodified, to
    -- prevent "file changed on disk" prompts.
    if target_bufnr then
      local ok2, new_lines = pcall(vim.fn.readfile, target_path)
      if ok2 then
        vim.api.nvim_buf_call(target_bufnr, function()
          -- Same reasoning as the modified-buffer branch above: this silent
          -- disk-sync reload must not become its own undo step either.
          pcall(vim.cmd, 'undojoin')
          pcall(vim.api.nvim_buf_set_lines, target_bufnr, 0, -1, false, new_lines)
        end)
        pcall(vim.api.nvim_set_option_value, 'modified', false, { buf = target_bufnr })
        require('pkm.syntax').refresh_fold(target_bufnr)
      end
    end
  end
end

-- =============================================================================
-- SECTION: Legacy migration
-- =============================================================================
--- Migrate legacy inline links to YAML
local function migrate_legacy_links(filepath)
  local content = vim.fn.readfile(filepath)
  local fm, content_start = yaml.parse_frontmatter(content)
  if not fm then return end
  
  ensure_grouped_cited_by(fm)
  
  local legacy_links = {}
  local clean_content = {}
  local pattern = "%*Linked from: %[%[([^%]]+)%]%]%*"
  
  for i = content_start, #content do
    local line = content[i]
    local basename = line:match(pattern)
    if basename then
      table.insert(legacy_links, basename)
    else
      table.insert(clean_content, line)
    end
  end
  
  if #legacy_links > 0 then
    local items_map = M.get_citable_items_map()
    for _, basename in ipairs(legacy_links) do
      for id, data in pairs(items_map) do
        if data.basename == basename then
          local group = "notes"
          if data.type == "bib" then group = "bib" end
          if data.type == "journal" then group = "journal" end
          if data.type == "scratch" then group = "scratch" end
          
          local exists = false
          if fm.cited_by[group] then
              for _, entry in ipairs(fm.cited_by[group]) do
                if entry.identifier == id then exists = true break end
              end
          end
          
          if not exists then
            table.insert(fm.cited_by[group], {
              identifier = id,
              title = data.title,
              link = "[[" .. basename .. "]]"
            })
          end
          break
        end
      end
    end
    
    local fm_lines = yaml.generate_yaml(fm)
    local final_content = {"---"}
    for _, line in ipairs(fm_lines) do table.insert(final_content, line) end
    table.insert(final_content, "---")
    if #clean_content > 0 and clean_content[1] ~= "" then
      table.insert(final_content, "")
    end
    for _, line in ipairs(clean_content) do
      table.insert(final_content, line)
    end
    vim.fn.writefile(final_content, filepath)
    require('pkm.index').invalidate(filepath)
  end
end

-- =============================================================================
-- SECTION: Reference synchronization
-- =============================================================================
--- Scan a file for citation tokens and rebuild its cites/cited_by frontmatter.
--- When target_file is provided, reads from and writes to disk (sync mode).
--- When nil, reads from the current buffer (interactive mode).
--- Also handles legacy inline backlink migration when in sync mode.
---@param target_file string|nil Absolute path, or nil to use current buffer
function M.update_references(target_file)
  -- 1. Determine Context (Buffer vs Disk)
  local current_path = target_file or vim.fn.expand("%:p")
  if not current_path or current_path == "" then return end

  -- Guard: abort silently if the file no longer exists at this path.
  -- This happens when sync_filename_on_save renames the file before
  -- the BufWritePost autocmd calls update_references(old_filepath).
  if target_file and vim.fn.filereadable(target_file) == 0 then return end
  
  -- Only migrate legacy links if we are working on disk (Sync mode)
  if target_file then
    migrate_legacy_links(current_path)
  end
  
  -- 2. Read Content
  local lines
  if target_file then
    lines = vim.fn.readfile(target_file) -- Read from disk
  else
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) -- Read from buffer
  end

  local frontmatter, content_start = yaml.parse_frontmatter(lines)
  if not frontmatter then return end
  
  -- 3. Ensure structure
  if not frontmatter.cites then
    frontmatter.cites = {notes = {}, bib = {}, journal = {}, scratch = {}}
  elseif type(frontmatter.cites) == "table" then
    if not frontmatter.cites.notes and not frontmatter.cites.bib then
        local old_array = frontmatter.cites
        frontmatter.cites = {notes = {}, bib = {}, journal = {}, scratch = {}}
        for _, entry in ipairs(old_array) do
          if type(entry) == "table" and entry.identifier then
            local group = "notes"
            if entry.type == "bib" then group = "bib" end
            if entry.type == "journal" then group = "journal" end
            if entry.type == "scratch" then group = "scratch" end
            table.insert(frontmatter.cites[group], {
              identifier = entry.identifier,
              title = entry.title,
              link = entry.link
            })
          end
        end
    end
  end
  
  -- 4. Map Old Citations
  local old_cites_map = {}
  local groups = {"notes", "bib", "journal", "scratch"}
  for _, g in ipairs(groups) do
    if frontmatter.cites[g] then
        for _, entry in ipairs(frontmatter.cites[g]) do
            if entry.identifier then old_cites_map[entry.identifier] = true end
        end
    end
  end
  
  -- 5. Scan Text for Citations
  local all_items_map = M.get_citable_items_map()
  local all_items_by_short = {}
  for id, data in pairs(all_items_map) do
    local short = data.type .. "|" .. (id:match("note%-(%d+)") or id:match("bib%-(%d+)") or id)
    all_items_by_short[short] = {id = id, data = data}
  end
  
  local new_cites = {notes = {}, bib = {}, journal = {}, scratch = {}}
  local new_cites_map = {}
  
  for i = content_start, #lines do
    for match in lines[i]:gmatch("[%a][%w_%-]*%[[%w%-_]+%]") do
      local cite_type, short_id = M.parse_citation(match)
      if cite_type and short_id then
        local key = cite_type .. "|" .. short_id
        local item = all_items_by_short[key]
        
        -- Removed filereadable check to prevent encoding drops
        if item then
            if not new_cites_map[item.id] then
              local group = "notes"
              if item.data.type == "bib" then group = "bib" end
              if item.data.type == "journal" then group = "journal" end
              if item.data.type == "scratch" then group = "scratch" end
              table.insert(new_cites[group], {
                identifier = item.id,
                title = item.data.title,
                link = "[[" .. item.data.basename .. "]]"
              })
              new_cites_map[item.id] = true
            end
        end
      end
    end
  end
  
  for _, g in ipairs(groups) do
      table.sort(new_cites[g], function(a, b) return a.identifier < b.identifier end)
  end
  
  frontmatter.cites = new_cites
  
  -- 6. Save (Buffer or Disk)
  yaml.save_frontmatter(frontmatter, content_start, target_file)
  if target_file then
    require('pkm.index').invalidate(target_file)
  end
  
  -- 7. Cross-Update Backlinks
  for id, _ in pairs(old_cites_map) do
    if not new_cites_map[id] then
      local target_item = all_items_map[id]
      -- Removed filereadable check here as well
      if target_item then
        manage_backlink(current_path, target_item.path, "remove")
      end
    end
  end
  
  for id, _ in pairs(new_cites_map) do
    if not old_cites_map[id] then
      local target_item = all_items_map[id]
      -- Removed filereadable check here as well
      if target_item then
        manage_backlink(current_path, target_item.path, "add")
      end
    end
  end
end

-- =============================================================================
-- SECTION: Citation insertion
-- =============================================================================
--- Insert a citation string at the current cursor position and trigger a
--- reference sync on the current buffer. Called by Telescope after selection.
---@param selected {type:string, short_id:string}
function M.complete_insertion(selected)
    if not selected then return end
    local citation = string.format("%s[%s]", selected.type, selected.short_id)
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    vim.api.nvim_set_current_line(line:sub(1, col) .. citation .. line:sub(col + 1))
    vim.api.nvim_win_set_cursor(0, {row, col + #citation})
    
    -- Wrapped to prevent passing random arguments to update_references
    vim.schedule(function() M.update_references() end)
end


--- Jump to the note referenced by the citation token under the cursor.
--- Reads the word under cursor, resolves it through the citable items map,
--- and opens the target file with :edit.
function M.goto_citation()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-based column
  
  local citation_match = nil
  local current_idx = 1
  
  -- Robust loop to find the exact citation under cursor
  while true do
    -- Find next pattern match
    local start_pos, end_pos, type_match, id_match = line:find("(%w+)%[([%w%-_]+)%]", current_idx)
    
    if not start_pos then break end
    
    -- Check if cursor is within this match
    if col >= start_pos and col <= end_pos then
      citation_match = {type = type_match, id = id_match}
      break
    end
    
    -- Move search forward
    current_idx = end_pos + 1
  end
  
  if not citation_match then
    vim.notify("No citation under cursor", vim.log.levels.WARN)
    return
  end
  
  local items = M.get_citable_items_for_picker()
  for _, item in ipairs(items) do
    if item.type == citation_match.type and item.short_id == citation_match.id then
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
      return
    end
  end
  
  vim.notify("Citation target not found in library: " .. citation_match.type .. "[" .. citation_match.id .. "]", vim.log.levels.ERROR)
end

--- Propagate a note rename or deletion across all files in the wiki.
--- Updates [[wiki-links]] in note bodies and identifier/link fields in
--- cites/cited_by frontmatter. Pass "__DELETED__" as new_basename to
--- strike through links instead of replacing them.
---@param old_basename string Filename without extension before rename
---@param new_basename string Filename without extension after rename, or "__DELETED__"
---@param new_title string|nil New title to update in citation entries, or nil
function M.update_references_on_rename(old_basename, new_basename, new_title)
  local _, old_id = M.get_note_type_and_id(old_basename .. ".md")
  local _, new_id = nil, nil
  if new_basename ~= "__DELETED__" then
      _, new_id = M.get_note_type_and_id(new_basename .. ".md")
  end
  
  if not old_id then return end
  
  local search_paths = {
    config.folders.consolidated,
    config.folders.journal, 
    config.folders.scratchpad
  }
  
  for _, folder in ipairs(search_paths) do
    if folder then
        local search_path = utils.join(config.root_path, folder)
        local files = vim.fn.glob(search_path .. "/*.md", false, true)
        if type(files) ~= "table" then files = {} end
        
        for _, file in ipairs(files) do
          local content = vim.fn.readfile(file)
          local modified = false
          local new_content_lines = {}
          
          -- 1. Body replacement (Inline links)
          for _, line in ipairs(content) do
            local new_line = line
            if new_basename == "__DELETED__" then
                local link_pattern = "%[%[" .. vim.pesc(old_basename) .. "%]%]"
                if line:match(link_pattern) then
                    new_line = line:gsub(link_pattern, "~~" .. old_basename .. "~~ (deleted)")
                    modified = true
                end
            else
                new_line = line:gsub(
                  "%[%[" .. vim.pesc(old_basename) .. "%]%]",
                  "[[" .. new_basename .. "]]"
                )
                if new_line ~= line then modified = true end
            end
            table.insert(new_content_lines, new_line)
          end
          
          -- 2. YAML replacement
          local fm, content_start = yaml.parse_frontmatter(new_content_lines)
          if fm then
             local lists_to_check = {}
             if fm.cites then table.insert(lists_to_check, fm.cites) end
             if fm.cited_by then table.insert(lists_to_check, fm.cited_by) end
             
             for _, list in ipairs(lists_to_check) do
                for _, group_key in ipairs({"notes", "bib", "journal", "scratch"}) do
                    if list[group_key] then
                        local new_group_list = {}
                        local list_modified = false
                        
                        for _, item in ipairs(list[group_key]) do
                            if type(item) == "table" and item.identifier == old_id then
                                if new_basename == "__DELETED__" then
                                    list_modified = true
                                    modified = true
                                else
                                    item.link = "[[" .. new_basename .. "]]"
                                    if new_id then item.identifier = new_id end
                                    if new_title and item.title then item.title = new_title end
                                    table.insert(new_group_list, item)
                                    modified = true
                                end
                            else
                                table.insert(new_group_list, item)
                            end
                        end
                        
                        if list_modified then
                            list[group_key] = new_group_list
                        end
                    end
                end
             end
          end
          
          if modified then
               if fm then
                  local fm_lines = yaml.generate_yaml(fm)
                  local final_content = {"---"}
                  for _, line in ipairs(fm_lines) do table.insert(final_content, line) end
                  table.insert(final_content, "---")
                  if #new_content_lines >= content_start and new_content_lines[content_start] ~= "" then
                    table.insert(final_content, "")
                  end
                  for i = content_start, #new_content_lines do
                    table.insert(final_content, new_content_lines[i])
                  end
                  vim.fn.writefile(final_content, file)
                  require('pkm.index').invalidate(file)
              else
                  vim.fn.writefile(new_content_lines, file)
                  require('pkm.index').invalidate(file)
              end
          end
        end
    end
  end
end

-- =============================================================================
-- SECTION: Cleanup
-- =============================================================================
--- Remove all frontmatter references to a deleted note across the entire wiki.
--- Removes entries from cites and cited_by in every affected file.
--- Also strikes through inline [[wiki-links]] in note bodies.
---@param filepath string Absolute path of the note being deleted
function M.cleanup_deleted_note(filepath)
    -- 1. Get the list of notes that the deleted note cited
    -- (We need to remove the "Cited by" backlink from them)
    local content = vim.fn.readfile(filepath)
    local fm = yaml.parse_frontmatter(content)
    
    if fm and fm.cites then
        local items_map = M.get_citable_items_map()
        local groups = {"notes", "bib", "journal", "scratch"}
        
        for _, group in ipairs(groups) do
            if fm.cites[group] then
                for _, entry in ipairs(fm.cites[group]) do
                    if entry.identifier then
                        local target = items_map[entry.identifier]
                        if target then
                             -- Force remove my backlink from the target
                             manage_backlink(filepath, target.path, "remove")
                        end
                    end
                end
            end
        end
    end

    -- 2. Remove references TO this deleted note from other files
    M.update_references_on_rename(
        vim.fn.fnamemodify(filepath, ":t:r"), 
        "__DELETED__", 
        nil
    )
end

-- =============================================================================
-- SECTION: Tag merging
-- =============================================================================
--- Merge a list of source tags into a single target tag across all notes.
--- Files containing any source tag will have those tags replaced by the target.
--- If the target tag is already present in a file alongside a source tag,
--- the source is removed and no duplicate is introduced.
--- @param source_tags table  List of tag strings to merge from
--- @param target_tag  string Tag string to merge into
--- @return number Count of modified files
function M.merge_tags(source_tags, target_tag)
  local source_set = {}
  for _, t in ipairs(source_tags) do source_set[t] = true end

  local search_paths = {
    config.folders.consolidated,
    config.folders.journal,
    config.folders.scratchpad,
  }

  local modified = 0

  for _, folder in ipairs(search_paths) do
    if folder then
      local search_path = utils.join(config.root_path, folder)
      local files = vim.fn.glob(search_path .. utils.sep .. "*.md", false, true)
      if type(files) ~= "table" then files = {} end

      for _, file in ipairs(files) do
        local content = vim.fn.readfile(file)
        local fm, _ = yaml.parse_frontmatter(content)

        if fm and type(fm.tags) == "table" then
          local new_tags      = {}
          local target_seen   = false  -- prevents duplicating the target
          local changed       = false

          for _, tag in ipairs(fm.tags) do
            if source_set[tag] then
              -- This is a source tag: replace with target (once)
              changed = true
              if not target_seen then
                table.insert(new_tags, target_tag)
                target_seen = true
              end
              -- source tag is dropped
            elseif tag == target_tag then
              -- Target already present; keep it, but don't add twice
              if not target_seen then
                table.insert(new_tags, tag)
                target_seen = true
              end
            else
              table.insert(new_tags, tag)
            end
          end

          if changed then
            fm.tags = new_tags
            yaml.save_frontmatter(fm, nil, file)
            require('pkm.index').invalidate(file)
            modified = modified + 1
          end
        end
      end
    end
  end

  return modified
end

return M
