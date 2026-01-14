-- lua/pkm/citations.lua
-- FIXED VERSION: Addresses all three critical issues
-- 1. Prevents top-level field corruption
-- 2. Uses grouped cited_by structure
-- 3. Migrates legacy links
-- 4. Implements aggregate note validation

local M = {}
local config = {}
local yaml = nil
local path_sep = package.config:sub(1, 1)

function M.setup(user_config)
  config = user_config
  yaml = require('pkm.yaml')
end

local function join_path(...) 
  return table.concat({...}, path_sep) 
end

function M.parse_citation(text) 
  return text:match("(%w+)%[([%w%-_]+)%]") 
end

--- Get note type and identifier from path (e.g., "note-0001")
function M.get_note_type_and_id(filepath)
  local filename = vim.fn.fnamemodify(filepath, ":t:r")
  local number, note_type = filename:match("^(%d+)_([a-z]+)_")
  if number and note_type then
    local item_type = (note_type == "bib") and "bib" or "note"
    return item_type, item_type .. "-" .. number
  end
  local prefix, timestamp = filename:match("^(.+)_(.+)$")
  if prefix == "journal" or prefix == "scratch" then 
    return prefix, timestamp 
  end
  return nil, nil
end

function M.get_note_title(filepath)
  local content = vim.fn.readfile(filepath)
  local fm, _ = yaml.parse_frontmatter(content)
  return (fm and fm.title and fm.title ~= "") 
    and fm.title 
    or vim.fn.fnamemodify(filepath, ":t:r"):gsub("_", " ")
end

--- Get a map of all citable items, keyed by their full unique identifier
function M.get_citable_items_map()
  local items_map = {}
  local search_paths = {
    config.folders.consolidated, 
    config.folders.journal, 
    config.folders.scratchpad
  }
  
  for _, folder in ipairs(search_paths) do
    local files = vim.fn.glob(join_path(config.root_path, folder) .. "/*.md", false, true)
    for _, file in ipairs(files) do
      local type, id = M.get_note_type_and_id(file)
      if type and id then
        items_map[id] = {
          path = file,
          basename = vim.fn.fnamemodify(file, ":t:r"),
          type = type,
          title = M.get_note_title(file)
        }
      end
    end
  end
  
  return items_map
end

--- Get a formatted list of citable items for vim.ui.select
function M.get_citable_items_for_picker()
  local items = {}
  local all_items_map = M.get_citable_items_map()
  
  for id, data in pairs(all_items_map) do
    local short_id = id:match("note%-(%d+)") 
      or id:match("bib%-(%d+)") 
      or id:match("%d%d%d%d%-%d%d%-%d%d") 
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

--- FIXED: Initialize or migrate cited_by to new grouped structure
--- @param frontmatter table The frontmatter to check/migrate
--- @return boolean True if migration occurred
local function ensure_grouped_cited_by(frontmatter)
  if not frontmatter.cited_by then
    frontmatter.cited_by = {notes = {}, bib = {}}
    return false
  end
  
  -- Check if already in new format
  if frontmatter.cited_by.notes or frontmatter.cited_by.bib then
    -- Ensure both keys exist
    frontmatter.cited_by.notes = frontmatter.cited_by.notes or {}
    frontmatter.cited_by.bib = frontmatter.cited_by.bib or {}
    return false
  end
  
  -- Migrate from old flat format
  local old_array = frontmatter.cited_by
  local new_structure = {notes = {}, bib = {}}
  
  for _, entry in ipairs(old_array) do
    if type(entry) == "table" and entry.identifier then
      local clean_entry = {
        identifier = entry.identifier,
        title = entry.title,
        link = entry.link
      }
      
      if entry.type == "bib" then
        table.insert(new_structure.bib, clean_entry)
      else
        table.insert(new_structure.notes, clean_entry)
      end
    end
  end
  
  frontmatter.cited_by = new_structure
  return true
end

--- FIXED: Adds or removes a backlink from a target file
--- Now uses grouped structure and prevents top-level corruption
local function manage_backlink(citing_path, target_path, action)
  local citing_type, citing_id = M.get_note_type_and_id(citing_path)
  if not citing_type or not citing_id then return end
  
  -- VALIDATION: Check if target is aggregate note
  local target_content = vim.fn.readfile(target_path)
  local target_fm, _ = yaml.parse_frontmatter(target_content)
  
  if target_fm and target_fm.type == "agg" then
    vim.notify(
      "Cannot cite aggregate notes. Aggregates are collections only.", 
      vim.log.levels.ERROR
    )
    return
  end
  
  -- Read and parse target file
  local content = vim.fn.readfile(target_path)
  local fm, content_start = yaml.parse_frontmatter(content)
  if not fm then return end
  
  -- CRITICAL FIX: Ensure grouped structure
  local migrated = ensure_grouped_cited_by(fm)
  
  -- Determine which group to modify
  local group = (citing_type == "bib") and "bib" or "notes"
  
  -- Check if entry exists
  local found_index = nil
  for i, backlink in ipairs(fm.cited_by[group]) do
    if backlink.identifier == citing_id then
      found_index = i
      break
    end
  end
  
  local modified = migrated
  
  if action == "add" and not found_index then
    -- Add new backlink
    table.insert(fm.cited_by[group], {
      identifier = citing_id,
      title = M.get_note_title(citing_path),
      link = "[[" .. vim.fn.fnamemodify(citing_path, ":t:r") .. "]]"
    })
    modified = true
    
  elseif action == "remove" and found_index then
    -- Remove backlink
    table.remove(fm.cited_by[group], found_index)
    modified = true
  end
  
  if modified then
    -- Sort both groups
    table.sort(fm.cited_by.notes, function(a, b) 
      return (a.identifier or "") < (b.identifier or "") 
    end)
    table.sort(fm.cited_by.bib, function(a, b) 
      return (a.identifier or "") < (b.identifier or "") 
    end)
    
    -- CRITICAL: Save with context-aware function that won't corrupt top-level fields
    yaml.save_frontmatter(fm, content_start, target_path)
  end
end

--- FIXED: Migrate legacy inline links to YAML
--- Detects *Linked from: [[basename]]* and moves to cited_by
local function migrate_legacy_links(filepath)
  local content = vim.fn.readfile(filepath)
  local fm, content_start = yaml.parse_frontmatter(content)
  
  if not fm then return end
  
  -- Ensure grouped structure
  ensure_grouped_cited_by(fm)
  
  local legacy_links = {}
  local clean_content = {}
  local pattern = "%*Linked from: %[%[([^%]]+)%]%]%*"
  
  -- Scan document body for legacy links
  for i = content_start, #content do
    local line = content[i]
    local basename = line:match(pattern)
    
    if basename then
      table.insert(legacy_links, basename)
      -- Don't add this line to clean content (removes it)
    else
      table.insert(clean_content, line)
    end
  end
  
  -- Process found legacy links
  if #legacy_links > 0 then
    local items_map = M.get_citable_items_map()
    
    for _, basename in ipairs(legacy_links) do
      -- Find the note in our map
      local found = false
      for id, data in pairs(items_map) do
        if data.basename == basename then
          local group = (data.type == "bib") and "bib" or "notes"
          
          -- Check if already exists
          local exists = false
          for _, entry in ipairs(fm.cited_by[group]) do
            if entry.identifier == id then
              exists = true
              break
            end
          end
          
          if not exists then
            table.insert(fm.cited_by[group], {
              identifier = id,
              title = data.title,
              link = "[[" .. basename .. "]]"
            })
          end
          
          found = true
          break
        end
      end
      
      if not found then
        vim.notify(
          "Warning: Legacy link not found in system: " .. basename, 
          vim.log.levels.WARN
        )
      end
    end
    
    -- Reconstruct file with updated frontmatter and clean content
    local fm_lines = yaml.generate_yaml(fm)
    local final_content = {"---"}
    for _, line in ipairs(fm_lines) do 
      table.insert(final_content, line) 
    end
    table.insert(final_content, "---")
    
    if #clean_content > 0 and clean_content[1] ~= "" then
      table.insert(final_content, "")
    end
    
    for _, line in ipairs(clean_content) do
      table.insert(final_content, line)
    end
    
    vim.fn.writefile(final_content, filepath)
    vim.notify(
      "Migrated " .. #legacy_links .. " legacy link(s) to YAML", 
      vim.log.levels.INFO
    )
  end
end

--- ENHANCED: Update references with file existence validation
--- Now skips citations to deleted files
function M.update_references()
  local current_path = vim.fn.expand("%:p")
  if not current_path or current_path == "" then return end
  
  -- Migrate any legacy links first
  migrate_legacy_links(current_path)
  
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, content_start = yaml.parse_frontmatter(lines)
  if not frontmatter then return end
  
  -- Ensure cites uses grouped structure
  if not frontmatter.cites then
    frontmatter.cites = {notes = {}, bib = {}}
  elseif type(frontmatter.cites) == "table" then
    if not frontmatter.cites.notes and not frontmatter.cites.bib then
      if #frontmatter.cites > 0 then
        local old_array = frontmatter.cites
        frontmatter.cites = {notes = {}, bib = {}}
        for _, entry in ipairs(old_array) do
          if type(entry) == "table" and entry.identifier then
            local group = (entry.type == "bib") and "bib" or "notes"
            table.insert(frontmatter.cites[group], {
              identifier = entry.identifier,
              title = entry.title,
              link = entry.link
            })
          end
        end
      else
        frontmatter.cites = {notes = {}, bib = {}}
      end
    end
  end
  
  -- Build maps of old references
  local old_cites_map = {}
  for _, entry in ipairs(frontmatter.cites.notes or {}) do
    if entry.identifier then old_cites_map[entry.identifier] = true end
  end
  for _, entry in ipairs(frontmatter.cites.bib or {}) do
    if entry.identifier then old_cites_map[entry.identifier] = true end
  end
  
  -- Find all citations in document body
  local all_items_map = M.get_citable_items_map()
  local all_items_by_short = {}
  
  for id, data in pairs(all_items_map) do
    local short = data.type .. "|" .. (id:match("note%-(%d+)") or id:match("bib%-(%d+)") or id)
    all_items_by_short[short] = {id = id, data = data}
  end
  
  local new_cites = {notes = {}, bib = {}}
  local new_cites_map = {}
  local skipped_citations = {}  -- Track citations to deleted files
  
  for i = content_start, #lines do
    for match in lines[i]:gmatch("%w+%[[%w%-_]+%]") do
      local cite_type, short_id = M.parse_citation(match)
      if cite_type and short_id then
        local key = cite_type .. "|" .. short_id
        local item = all_items_by_short[key]
        
        if item then
          -- VALIDATION: Check if file exists
          if vim.fn.filereadable(item.data.path) == 1 then
            if not new_cites_map[item.id] then
              local group = (item.data.type == "bib") and "bib" or "notes"
              table.insert(new_cites[group], {
                identifier = item.id,
                title = item.data.title,
                link = "[[" .. item.data.basename .. "]]"
              })
              new_cites_map[item.id] = true
            end
          else
            -- File doesn't exist - skip this citation
            table.insert(skipped_citations, {
              match = match,
              identifier = item.id,
              line = i - content_start + 1
            })
          end
        end
      end
    end
  end
  
  -- Report skipped citations
  if #skipped_citations > 0 then
    local msg = string.format(
      "Warning: Skipped %d citation(s) to deleted files. Run :PKMCleanupFrontmatter to mark them as deleted.",
      #skipped_citations
    )
    vim.notify(msg, vim.log.levels.WARN)
    
    -- Show details
    for _, skip in ipairs(skipped_citations) do
      vim.notify(
        string.format("  Line %d: %s (file not found)", skip.line, skip.match),
        vim.log.levels.WARN
      )
    end
  end
  
  -- Sort both groups
  table.sort(new_cites.notes, function(a, b) 
    return a.identifier < b.identifier 
  end)
  table.sort(new_cites.bib, function(a, b) 
    return a.identifier < b.identifier 
  end)
  
  frontmatter.cites = new_cites
  yaml.save_frontmatter(frontmatter, content_start)
  
  -- Update backlinks in all referenced files
  -- Remove backlinks for citations that were deleted
  for id, _ in pairs(old_cites_map) do
    if not new_cites_map[id] then
      local target_item = all_items_map[id]
      if target_item and vim.fn.filereadable(target_item.path) == 1 then
        manage_backlink(current_path, target_item.path, "remove")
      end
    end
  end
  
  -- Add backlinks for new citations
  for id, _ in pairs(new_cites_map) do
    if not old_cites_map[id] then
      local target_item = all_items_map[id]
      if target_item and vim.fn.filereadable(target_item.path) == 1 then
        manage_backlink(current_path, target_item.path, "add")
      end
    end
  end
  
  local msg = "References updated"
  if #skipped_citations > 0 then
    msg = msg .. string.format(" (%d stale citation(s) skipped)", #skipped_citations)
  end
  vim.notify(msg, vim.log.levels.INFO)
end

--- Insert citation with aggregate validation
function M.insert_citation()
  local items = M.get_citable_items_for_picker()
  if #items == 0 then return end
  
  vim.ui.select(items, {
    prompt = "Select item to cite:",
    format_item = function(item) return item.display end
  }, function(selected)
    if not selected then return end
    
    -- VALIDATION: Check if trying to cite an aggregate note
    local target_content = vim.fn.readfile(selected.path)
    local target_fm, _ = yaml.parse_frontmatter(target_content)
    
    if target_fm and target_fm.type == "agg" then
      vim.notify(
        "Cannot cite aggregate notes. They are collections only.", 
        vim.log.levels.ERROR
      )
      return
    end
    
    local citation = string.format("%s[%s]", selected.type, selected.short_id)
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    vim.api.nvim_set_current_line(
      line:sub(1, col) .. citation .. line:sub(col + 1)
    )
    vim.api.nvim_win_set_cursor(0, {row, col + #citation})
    
    vim.schedule(M.update_references)
  end)
end

--- ENHANCED: Comprehensive frontmatter cleanup with validation
--- Removes corrupted keys AND validates/removes stale references
function M.cleanup_frontmatter()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, content_start = yaml.parse_frontmatter(lines)
  
  if not frontmatter then 
    vim.notify("No frontmatter to clean", vim.log.levels.INFO)
    return 
  end
  
  local was_modified = false
  local cleanup_report = {
    corrupted_keys = {},
    stale_cites = {},
    stale_cited_by = {}
  }
  
  -- STEP 1: Remove obvious corrupted keys
  local corrupted_keys = {"link", "identifier", "short_id"}
  
  for _, key in ipairs(corrupted_keys) do
    if frontmatter[key] ~= nil then 
      frontmatter[key] = nil
      table.insert(cleanup_report.corrupted_keys, key)
      was_modified = true 
    end
  end
  
  -- STEP 2: Handle 'type' field specially
  if frontmatter.type then
    local filepath = vim.fn.expand("%:p")
    local actual_type = M.get_note_type_and_id(filepath)
    
    if actual_type == "bib" and frontmatter.type ~= "bib" then
      frontmatter.type = "bib"
      was_modified = true
    elseif actual_type ~= "bib" and frontmatter.type == "agg" then
      -- Keep agg type if intentional
    elseif actual_type ~= "bib" and frontmatter.type ~= "agg" then
      frontmatter.type = nil
      table.insert(cleanup_report.corrupted_keys, "type")
      was_modified = true
    end
  end
  
  -- STEP 3: Migrate and validate cited_by structure
  if frontmatter.cited_by then
    local migrated = ensure_grouped_cited_by(frontmatter)
    if migrated then
      was_modified = true
    end
    
    -- Validate entries in cited_by
    local all_items = M.get_citable_items_map()
    
    for _, group in ipairs({"notes", "bib"}) do
      if frontmatter.cited_by[group] then
        local valid_entries = {}
        
        for _, entry in ipairs(frontmatter.cited_by[group]) do
          if type(entry) == "table" and entry.identifier then
            local item = all_items[entry.identifier]
            
            -- Check if file exists
            if item and vim.fn.filereadable(item.path) == 1 then
              table.insert(valid_entries, entry)
            else
              -- Stale reference - file doesn't exist
              table.insert(cleanup_report.stale_cited_by, {
                group = group,
                identifier = entry.identifier,
                title = entry.title or "unknown"
              })
              was_modified = true
            end
          end
        end
        
        frontmatter.cited_by[group] = valid_entries
      end
    end
  end
  
  -- STEP 4: Migrate and validate cites structure
  if frontmatter.cites then
    if not frontmatter.cites.notes and not frontmatter.cites.bib then
      -- Migrate old format
      local old_array = frontmatter.cites
      frontmatter.cites = {notes = {}, bib = {}}
      
      for _, entry in ipairs(old_array) do
        if type(entry) == "table" and entry.identifier then
          local group = (entry.type == "bib") and "bib" or "notes"
          table.insert(frontmatter.cites[group], {
            identifier = entry.identifier,
            title = entry.title,
            link = entry.link
          })
        end
      end
      
      was_modified = true
    end
    
    -- Validate entries in cites
    local all_items = M.get_citable_items_map()
    
    for _, group in ipairs({"notes", "bib"}) do
      if frontmatter.cites[group] then
        local valid_entries = {}
        
        for _, entry in ipairs(frontmatter.cites[group]) do
          if type(entry) == "table" and entry.identifier then
            local item = all_items[entry.identifier]
            
            -- Check if file exists
            if item and vim.fn.filereadable(item.path) == 1 then
              table.insert(valid_entries, entry)
            else
              -- Stale reference - file doesn't exist
              table.insert(cleanup_report.stale_cites, {
                group = group,
                identifier = entry.identifier,
                title = entry.title or "unknown"
              })
              was_modified = true
            end
          end
        end
        
        frontmatter.cites[group] = valid_entries
      end
    end
  end
  
  -- STEP 5: Migrate legacy inline links
  local current_path = vim.fn.expand("%:p")
  if current_path ~= "" then
    migrate_legacy_links(current_path)
  end
  
  -- STEP 6: Save changes and report
  if was_modified then
    yaml.save_frontmatter(frontmatter, content_start)
    
    -- Build report message
    local messages = {}
    
    if #cleanup_report.corrupted_keys > 0 then
      table.insert(messages, string.format(
        "Removed %d corrupted key(s): %s",
        #cleanup_report.corrupted_keys,
        table.concat(cleanup_report.corrupted_keys, ", ")
      ))
    end
    
    if #cleanup_report.stale_cites > 0 then
      table.insert(messages, string.format(
        "Removed %d stale citation(s)",
        #cleanup_report.stale_cites
      ))
      
      for _, stale in ipairs(cleanup_report.stale_cites) do
        vim.notify(
          string.format("  - %s: %s (file not found)", 
            stale.group, stale.identifier),
          vim.log.levels.INFO
        )
      end
    end
    
    if #cleanup_report.stale_cited_by > 0 then
      table.insert(messages, string.format(
        "Removed %d stale backlink(s)",
        #cleanup_report.stale_cited_by
      ))
      
      for _, stale in ipairs(cleanup_report.stale_cited_by) do
        vim.notify(
          string.format("  - %s: %s (file not found)", 
            stale.group, stale.identifier),
          vim.log.levels.INFO
        )
      end
    end
    
    if #messages > 0 then
      vim.notify(table.concat(messages, "\n"), vim.log.levels.INFO)
    else
      vim.notify("Frontmatter structure updated", vim.log.levels.INFO)
    end
  else
    vim.notify("Frontmatter is clean", vim.log.levels.INFO)
  end
end

--- Go to citation source
function M.goto_citation()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  
  local citation_match = nil
  for match in line:gmatch("%w+%[[%w%-_]+%]") do
    local start_pos = line:find(vim.pesc(match), 1, true)
    if start_pos and col >= start_pos and col <= start_pos + #match then
      citation_match = match
      break
    end
  end
  
  if not citation_match then
    vim.notify("No citation under cursor", vim.log.levels.WARN)
    return
  end
  
  local cite_type, short_id = M.parse_citation(citation_match)
  if not cite_type or not short_id then return end
  
  local items = M.get_citable_items_for_picker()
  
  for _, item in ipairs(items) do
    if item.type == cite_type and item.short_id == short_id then
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
      return
    end
  end
  
  vim.notify("Citation not found: " .. citation_match, vim.log.levels.ERROR)
end

--- Show citation preview
function M.show_preview()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  
  local citation_match = nil
  for match in line:gmatch("%w+%[[%w%-_]+%]") do
    local start_pos = line:find(vim.pesc(match), 1, true)
    if start_pos and col >= start_pos and col <= start_pos + #match then
      citation_match = match
      break
    end
  end
  
  if not citation_match then return end
  
  local cite_type, short_id = M.parse_citation(citation_match)
  if not cite_type or not short_id then return end
  
  local items = M.get_citable_items_for_picker()
  local target = nil
  
  for _, item in ipairs(items) do
    if item.type == cite_type and item.short_id == short_id then
      target = item
      break
    end
  end
  
  if not target then return end
  
  local content = vim.fn.readfile(target.path)
  local _, content_start = yaml.parse_frontmatter(content)
  
  local preview_lines = {"---", "title: " .. target.title, "---", ""}
  
  local max_lines = 10
  for i = content_start, math.min(content_start + max_lines - 1, #content) do
    table.insert(preview_lines, content[i])
  end
  if #content > content_start + max_lines then
    table.insert(preview_lines, "...")
  end
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview_lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(15, vim.o.lines - 4)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    width = width,
    height = height,
    col = 1,
    row = 1,
    style = 'minimal',
    border = 'rounded',
  })
  
  vim.api.nvim_create_autocmd({"CursorMoved", "BufLeave"}, {
    buffer = 0,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
  })
end

--- Update all references when a note is renamed
function M.update_references_on_rename(old_basename, new_basename, new_title)
  local old_type, old_id = M.get_note_type_and_id(old_basename .. ".md")
  local new_type, new_id = M.get_note_type_and_id(new_basename .. ".md")
  
  if not old_id or not new_id then return end
  
  local search_paths = {
    join_path(config.root_path, config.folders.consolidated),
    join_path(config.root_path, config.folders.journal),
    join_path(config.root_path, config.folders.scratchpad),
  }
  
  for _, search_path in ipairs(search_paths) do
    local files = vim.fn.glob(search_path .. "/*.md", false, true)
    
    for _, file in ipairs(files) do
      local content = vim.fn.readfile(file)
      local modified = false
      
      -- Update inline links in body
      local new_content_lines = {}
      for _, line in ipairs(content) do
        local new_line = line:gsub(
          "%[%[" .. vim.pesc(old_basename) .. "%]%]",
          "[[" .. new_basename .. "]]"
        )
        if new_line ~= line then modified = true end
        table.insert(new_content_lines, new_line)
      end
      
      -- Update YAML references
      local fm, content_start = yaml.parse_frontmatter(new_content_lines)
      if fm then
        -- Ensure grouped structures
        if fm.cites then
          ensure_grouped_cited_by({cited_by = fm.cites})
          if not fm.cites.notes then fm.cites = {notes = {}, bib = {}} end
        end
        if fm.cited_by then
          ensure_grouped_cited_by(fm)
        end
        
        -- Update in both cites and cited_by
        for _, list_name in ipairs({"cites", "cited_by"}) do
          if fm[list_name] then
            for _, group_name in ipairs({"notes", "bib"}) do
              if fm[list_name][group_name] then
                for _, item in ipairs(fm[list_name][group_name]) do
                  if type(item) == "table" and item.identifier == old_id then
                    item.link = "[[" .. new_basename .. "]]"
                    item.identifier = new_id
                    if new_title and item.title then 
                      item.title = new_title 
                    end
                    modified = true
                  end
                end
              end
            end
          end
        end
      end
      
      if modified then
        if fm then
          local fm_lines = yaml.generate_yaml(fm)
          local final_content = {"---"}
          for _, line in ipairs(fm_lines) do 
            table.insert(final_content, line) 
          end
          table.insert(final_content, "---")
          if #new_content_lines >= content_start and new_content_lines[content_start] ~= "" then
            table.insert(final_content, "")
          end
          for i = content_start, #new_content_lines do
            table.insert(final_content, new_content_lines[i])
          end
          vim.fn.writefile(final_content, file)
        else
          vim.fn.writefile(new_content_lines, file)
        end
      end
    end
  end
end

--- ENHANCED: Complete bidirectional cleanup when a note is deleted
--- Handles both: removing deleted note from others AND removing others from deleted note's targets
--- @param deleted_path string Path to the deleted note
function M.cleanup_deleted_note(deleted_path)
  local deleted_type, deleted_id = M.get_note_type_and_id(deleted_path)
  if not deleted_type or not deleted_id then 
    vim.notify("Cannot determine note type/ID for cleanup", vim.log.levels.WARN)
    return 
  end
  
  local deleted_basename = vim.fn.fnamemodify(deleted_path, ":t:r")
  
  -- STEP 1: Read the deleted note's citations BEFORE it's gone
  -- We need to know who the deleted note was citing so we can remove backlinks
  local deleted_note_citations = {notes = {}, bib = {}}
  
  if vim.fn.filereadable(deleted_path) == 1 then
    local content = vim.fn.readfile(deleted_path)
    local fm, _ = yaml.parse_frontmatter(content)
    
    if fm and fm.cites then
      -- Ensure grouped structure
      if fm.cites.notes and fm.cites.bib then
        deleted_note_citations = fm.cites
      elseif type(fm.cites) == "table" and #fm.cites > 0 then
        -- Old flat format - convert
        for _, entry in ipairs(fm.cites) do
          if type(entry) == "table" and entry.identifier then
            local group = (entry.type == "bib") and "bib" or "notes"
            table.insert(deleted_note_citations[group], entry)
          end
        end
      end
    end
  end
  
  -- STEP 2: Remove deleted note's backlinks from its citation targets
  -- If deleted note cited A, B, C → remove deleted note from A's, B's, C's cited_by
  local items_map = M.get_citable_items_map()
  local citations_cleaned = 0
  
  for _, group in ipairs({"notes", "bib"}) do
    for _, citation in ipairs(deleted_note_citations[group]) do
      local target_item = items_map[citation.identifier]
      if target_item and vim.fn.filereadable(target_item.path) == 1 then
        local target_content = vim.fn.readfile(target_item.path)
        local target_fm, target_content_start = yaml.parse_frontmatter(target_content)
        
        if target_fm then
          ensure_grouped_cited_by(target_fm)
          
          local modified = false
          
          -- Remove deleted note from target's cited_by
          for _, target_group in ipairs({"notes", "bib"}) do
            local new_list = {}
            for _, backlink in ipairs(target_fm.cited_by[target_group]) do
              if not (type(backlink) == "table" and tostring(backlink.identifier) == tostring(deleted_id)) then
                table.insert(new_list, backlink)
              else
                modified = true
              end
            end
            target_fm.cited_by[target_group] = new_list
          end
          
          if modified then
            yaml.save_frontmatter(target_fm, target_content_start, target_item.path)
            citations_cleaned = citations_cleaned + 1
          end
        end
      end
    end
  end
  
  -- STEP 3: Remove deleted note from all other notes' cites and cited_by
  -- This is the original functionality - now enhanced
  local search_paths = {
    join_path(config.root_path, config.folders.consolidated),
    join_path(config.root_path, config.folders.journal),
    join_path(config.root_path, config.folders.scratchpad),
  }
  
  local files_cleaned = 0
  
  for _, search_path in ipairs(search_paths) do
    local files = vim.fn.glob(search_path .. path_sep .. "*.md", false, true)
    
    for _, file in ipairs(files) do
      if file ~= deleted_path then
        local content = vim.fn.readfile(file)
        local fm, content_start = yaml.parse_frontmatter(content)
        
        local modified = false
        
        -- Clean up YAML frontmatter
        if fm then
          ensure_grouped_cited_by(fm)
          if not fm.cites then fm.cites = {notes = {}, bib = {}} end
          ensure_grouped_cited_by({cited_by = fm.cites})
          
          -- Remove from both cites and cited_by
          for _, list_name in ipairs({"cites", "cited_by"}) do
            if fm[list_name] then
              for _, group_name in ipairs({"notes", "bib"}) do
                if fm[list_name][group_name] then
                  local new_list = {}
                  for _, item in ipairs(fm[list_name][group_name]) do
                    if not (type(item) == "table" and tostring(item.identifier) == tostring(deleted_id)) then
                      table.insert(new_list, item)
                    else
                      modified = true
                    end
                  end
                  fm[list_name][group_name] = new_list
                end
              end
            end
          end
        end
        
        -- Clean up inline wiki-links
        local body_modified = false
        local new_content = {}
        local link_pattern = "%[%[" .. vim.pesc(deleted_basename) .. "%]%]"
        
        for i = content_start, #content do
          local line = content[i]
          if line:match(link_pattern) then
            line = line:gsub(link_pattern, "~~" .. deleted_basename .. "~~ (deleted)")
            body_modified = true
          end
          table.insert(new_content, line)
        end
        
        -- Save changes if anything was modified
        if modified or body_modified then
          local final_content = {}
          
          if fm then
            local fm_lines = yaml.generate_yaml(fm)
            table.insert(final_content, "---")
            for _, line in ipairs(fm_lines) do 
              table.insert(final_content, line)
            end
            table.insert(final_content, "---")
            
            if #content >= content_start and content[content_start] ~= "" then
              table.insert(final_content, "")
            end
          end
          
          if body_modified then
            for _, line in ipairs(new_content) do
              table.insert(final_content, line)
            end
          else
            for i = content_start, #content do
              table.insert(final_content, content[i])
            end
          end
          
          vim.fn.writefile(final_content, file)
          files_cleaned = files_cleaned + 1
        end
      end
    end
  end
  
  -- Report summary
  local total_cleaned = citations_cleaned + files_cleaned
  vim.notify(
    string.format(
      "Cleanup complete: %d backlink(s) removed from targets, %d file(s) updated", 
      citations_cleaned, files_cleaned
    ),
    vim.log.levels.INFO
  )
end

return M
