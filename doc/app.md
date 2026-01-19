## ./citations.lua
```lua
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
```

## ./init.lua
```lua
-- lua/pkm/init.lua
-- UPDATED for plugin use
local M = {}

-- Detect OS once at module load
local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
local is_wsl = vim.fn.has('wsl') == 1

-- Configuration with cross-platform defaults
M.config = {
  -- Auto-detect root path based on OS
  root_path = (function()
    if is_windows then
      return vim.fn.expand('~/Documents/Notes')
    elseif is_wsl then
      -- WSL: Default to Windows user directory
      local username = vim.fn.getenv('USER')
      return '/mnt/c/Users/' .. username .. '/Documents/Notes'
    else
      return vim.fn.expand('~/Documents/Notes')
    end
  end)(),
  
  folders = {
    scratchpad = "01-Scratchpad",
    journal = "02-Journal",
    consolidated = "03-Consolidated",
  },

  sync = {
    enabled = true,
    auto_rename = true,
    auto_update_citations = true,
    auto_sync_on_save = true,
    validate_on_sync = true,
    notify_changes = true,
  }, 

  frontmatter_templates = {
    consolidated = {
      title = "", 
      author = "", 
      created_on = "ISO8601", 
      last_updated_on = "ISO8601",
      tags = {}, 
      status = "draft",
      cites = {notes = {}, bib = {}},
      cited_by = {notes = {}, bib = {}},
    },
    journal = {
      created_on = "ISO8601", 
      last_updated_on = "ISO8601", 
      author = "", 
      tags = {},
      location = nil,
      cites = {notes = {}, bib = {}},
      cited_by = {notes = {}, bib = {}},
    },
    bibliography = {
      title = "", 
      source_author = "", 
      note_author = "", 
      created_on = "ISO8601",
      last_updated_on = "ISO8601", 
      citation = "", 
      source_type = "book",
      source_location = "", 
      tags = {},
      cites = {notes = {}, bib = {}},
      cited_by = {notes = {}, bib = {}},
    },
    scratchpad = {
      created_on = "ISO8601", 
      last_updated_on = "ISO8601",
      cites = {notes = {}, bib = {}},
      cited_by = {notes = {}, bib = {}},
    },
  },
  
  citation = {
    inline_format = "%s[%s]",
    auto_number = true,
  },
  
  timestamp = {
    unknown_time_marker = "99-99-99", 
    default_format = "full", 
    auto_timestamp = true,
    prompt_on_create = false,
    formats = {
      full = "%Y-%m-%d_%H-%M-%S", 
      date_time = "%Y-%m-%d_%H-%M",
      date_only = "%Y-%m-%d", 
      date_unknown = "%Y-%m-%d_99-99-99",
    },
  },
  
  user = {
    name = "", 
    email = "", 
    institution = "",
  },
  
  keymaps = {},
}

-- Load submodules (lazy loaded)
local yaml = nil
local timestamp = nil
local citations = nil
local notes = nil
local journal = nil
local ui = nil

local function load_modules()
  if not yaml then
    yaml = require('pkm.yaml')
    timestamp = require('pkm.timestamp')
    citations = require('pkm.citations')
    notes = require('pkm.notes')
    journal = require('pkm.journal')
    ui = require('pkm.ui')
  end
end

--- Setup function to initialize the PKM system
--- @param user_config table|nil User configuration
function M.setup(user_config)
  -- Deep merge user config
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
  
  -- Fill in author fields if user.name is provided
  if M.config.user.name and M.config.user.name ~= "" then
    M.config.frontmatter_templates.consolidated.author = M.config.user.name
    M.config.frontmatter_templates.journal.author = M.config.user.name
    M.config.frontmatter_templates.bibliography.note_author = M.config.user.name
  end
  
  -- Load and setup all modules
  load_modules()
  
  yaml.setup(M.config)
  timestamp.setup(M.config)
  citations.setup(M.config)
  notes.setup(M.config)
  journal.setup(M.config)
  ui.setup(M.config)

  -- Register commands
  M.register_commands()

  -- Setup keymaps if provided
  if M.config.keymaps and next(M.config.keymaps) then
    M.setup_keymaps(M.config.keymaps)
  end

  -- Setup sync if enabled
  if M.config.sync.enabled then
    if M.config.sync.auto_sync_on_save then
      M.setup_sync_autocmds()
    else
      M.setup_basic_sync_autocmds()
    end
  end
  
  vim.notify("PKM System initialized", vim.log.levels.INFO)
end

--- Register all PKM commands
function M.register_commands()
  -- Note creation commands
  vim.api.nvim_create_user_command("PKMNewNote", function(opts)
    local note_type = opts.args
    if note_type == "" then note_type = nil end
    notes.create_new_note(note_type)
  end, { nargs = "?", complete = function() return {"agg", "note", "bib"} end, desc = "Create new consolidated note" })
  
  vim.api.nvim_create_user_command("PKMNewJournal", function() journal.create_entry(true) end, { desc = "Create journal entry with current time" })
  vim.api.nvim_create_user_command("PKMNewJournalCustom", function() journal.create_entry_custom() end, { desc = "Create journal entry with custom time" })
  vim.api.nvim_create_user_command("PKMNewScratchpad", function() notes.create_scratchpad() end, { desc = "Create new scratchpad" })
  vim.api.nvim_create_user_command("PKMQuickCapture", function() notes.quick_capture() end, { desc = "Quick capture to scratchpad" })
  vim.api.nvim_create_user_command("PKMConvertNote", function() notes.convert_note() end, { desc = "Convert note type" })
  
  -- Citation commands
  vim.api.nvim_create_user_command("PKMInsertCitation", function() citations.insert_citation() end, { desc = "Insert citation" })
  vim.api.nvim_create_user_command("PKMUpdateReferences", function() citations.update_references() end, { desc = "Update cites list from text" })
  vim.api.nvim_create_user_command("PKMGotoCitation", function() citations.goto_citation() end, { desc = "Go to citation source" })
  vim.api.nvim_create_user_command("PKMShowCitationPreview", function() citations.show_preview() end, { desc = "Show citation preview" })
  
  -- Navigation commands
  vim.api.nvim_create_user_command("PKMLinkNote", function() notes.link_to_note() end, { desc = "Link to another note" })
  vim.api.nvim_create_user_command("PKMFollowLink", function() notes.follow_link() end, { desc = "Follow link under cursor" })
  vim.api.nvim_create_user_command("PKMBacklinks", function() notes.show_backlinks() end, { desc = "Show backlinks to current note" })
  
  -- Search commands
  vim.api.nvim_create_user_command("PKMSearch", function(opts) ui.search_notes(opts.args) end, { nargs = "?", desc = "Search across all notes" })
  vim.api.nvim_create_user_command("PKMBrowseTags", function() ui.browse_tags() end, { desc = "Browse notes by tags" })
  vim.api.nvim_create_user_command("PKMRecentJournals", function() journal.list_recent(10) end, { desc = "List recent journal entries" })
  
  -- Frontmatter commands
  vim.api.nvim_create_user_command("PKMUpdateFrontmatter", function() yaml.update_frontmatter() end, { desc = "Update YAML frontmatter" })
  vim.api.nvim_create_user_command("PKMValidateFrontmatter", function() yaml.validate_frontmatter() end, { desc = "Validate YAML frontmatter" })
  vim.api.nvim_create_user_command("PKMUpdateTimestamp", function() yaml.update_last_modified() end, { desc = "Update last_updated_on timestamp" })
  
  -- Utility commands
  vim.api.nvim_create_user_command("PKMStats", function() M.show_stats() end, { desc = "Show PKM statistics" })
  vim.api.nvim_create_user_command("PKMToggleAutoTimestamp", function()
    M.config.timestamp.auto_timestamp = not M.config.timestamp.auto_timestamp
    vim.notify("Auto timestamp: " .. (M.config.timestamp.auto_timestamp and "ON" or "OFF"), vim.log.levels.INFO)
  end, { desc = "Toggle automatic timestamps" })
  vim.api.nvim_create_user_command("PKMSetDefaultFormat", function(opts)
    local format = opts.args
    if format == "full" or format == "date_time" or format == "date_only" then
      M.config.timestamp.default_format = format
      vim.notify("Default timestamp format: " .. format, vim.log.levels.INFO)
    else
      vim.notify("Invalid format. Use: full, date_time, or date_only", vim.log.levels.ERROR)
    end
  end, { nargs = 1, complete = function() return {"full", "date_time", "date_only"} end, desc = "Set default timestamp format" })
  
  -- Cleanup and sync commands
  vim.api.nvim_create_user_command("PKMCleanupFrontmatter", function() citations.cleanup_frontmatter() end, { desc = "Remove corrupted frontmatter keys" })
  
  vim.api.nvim_create_user_command("PKMSync", function()
    local start_time = vim.loop.hrtime()
    citations.update_references()
    citations.cleanup_frontmatter()
    local elapsed = (vim.loop.hrtime() - start_time) / 1e6
    vim.notify(string.format("Synchronized all references (%.1fms)", elapsed), vim.log.levels.INFO)
  end, { desc = "Synchronize and validate all references" })

  vim.api.nvim_create_user_command("PKMToggleAutoSync", function()
    M.config.sync.auto_sync_on_save = not M.config.sync.auto_sync_on_save
    local status = M.config.sync.auto_sync_on_save and "enabled" or "disabled"
    vim.notify("Auto-sync on save: " .. status, vim.log.levels.INFO)
    vim.api.nvim_clear_autocmds({group = "PKMSync"})
    if M.config.sync.auto_sync_on_save then
      M.setup_sync_autocmds()
    else
      M.setup_basic_sync_autocmds()
    end
  end, { desc = "Toggle automatic reference synchronization" })

  vim.api.nvim_create_user_command("PKMValidate", function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local fm, content_start = yaml.parse_frontmatter(lines)
    if not fm then vim.notify("No frontmatter to validate.", vim.log.levels.WARN); return end

    local all_items = citations.get_citable_items_map()
    local report = {
      valid_cites = 0, stale_cites = {},
      valid_cited_by = 0, stale_cited_by = {},
      broken_inline = {}
    }

    if fm.cites then
      for _, group in ipairs({"notes", "bib"}) do
        if fm.cites[group] then
          for _, entry in ipairs(fm.cites[group]) do
            if type(entry) == "table" and entry.identifier then
              if not (all_items[entry.identifier] and vim.fn.filereadable(all_items[entry.identifier].path) == 1) then
                table.insert(report.stale_cites, { group = group, id = entry.identifier, title = entry.title or "unknown" })
              else
                report.valid_cites = report.valid_cites + 1
              end
            end
          end
        end
      end
    end

    if fm.cited_by then
      for _, group in ipairs({"notes", "bib"}) do
        if fm.cited_by[group] then
          for _, entry in ipairs(fm.cited_by[group]) do
            if type(entry) == "table" and entry.identifier then
              if not (all_items[entry.identifier] and vim.fn.filereadable(all_items[entry.identifier].path) == 1) then
                table.insert(report.stale_cited_by, { group = group, id = entry.identifier, title = entry.title or "unknown" })
              else
                report.valid_cited_by = report.valid_cited_by + 1
              end
            end
          end
        end
      end
    end

    for i = content_start, #lines do
      for match in lines[i]:gmatch("%[%[([^%]]+)%]%]") do
        local found = false
        for _, item in pairs(all_items) do
          if item.basename == match and vim.fn.filereadable(item.path) == 1 then
            found = true
            break
          end
        end
        if not found then table.insert(report.broken_inline, { line = i, link = match }) end
      end
    end

    local lines_report = {
      "=== Reference Validation Report ===", "",
      string.format("Valid citations: %d", report.valid_cites),
      string.format("Valid backlinks: %d", report.valid_cited_by), ""
    }
    if #report.stale_cites > 0 then
      table.insert(lines_report, string.format("Stale citations (%d):", #report.stale_cites))
      for _, stale in ipairs(report.stale_cites) do table.insert(lines_report, string.format("  - %s/%s: %s", stale.group, stale.id, stale.title)) end
      table.insert(lines_report, "")
    end
    if #report.stale_cited_by > 0 then
      table.insert(lines_report, string.format("Stale backlinks (%d):", #report.stale_cited_by))
      for _, stale in ipairs(report.stale_cited_by) do table.insert(lines_report, string.format("  - %s/%s: %s", stale.group, stale.id, stale.title)) end
      table.insert(lines_report, "")
    end
    if #report.broken_inline > 0 then
      table.insert(lines_report, string.format("Broken inline links (%d):", #report.broken_inline))
      for _, broken in ipairs(report.broken_inline) do table.insert(lines_report, string.format("  - Line %d: [[%s]]", broken.line, broken.link)) end
      table.insert(lines_report, "")
    end
    if #report.stale_cites == 0 and #report.stale_cited_by == 0 and #report.broken_inline == 0 then
      table.insert(lines_report, "✓ All references are valid!")
    else
      table.insert(lines_report, "\nRun :PKMSync to clean up stale references")
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_report)
    local width, height = 80, math.min(#lines_report + 2, 25)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor', width = width, height = height,
      col = (vim.o.columns - width) / 2, row = (vim.o.lines - height) / 2,
      style = 'minimal', border = 'rounded', title = " PKM Validation Report ", title_pos = 'center',
    })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
  end, { desc = "Validate reference integrity" })
  
  vim.api.nvim_create_user_command("PKMDeleteNote", function() M.delete_note_safely() end, { desc = "Delete note and clean up references" })
end

--- Setup key mappings
function M.setup_keymaps(keymaps)
  local function map(mode, lhs, rhs, opts)
    opts = opts or {}
    opts.silent = opts.silent ~= false
    vim.keymap.set(mode, lhs, rhs, opts)
  end
  
  if keymaps.new_note then map('n', keymaps.new_note, ':PKMNewNote<CR>', { desc = "New note" }) end
  if keymaps.new_journal then map('n', keymaps.new_journal, ':PKMNewJournal<CR>', { desc = "New journal (current time)" }) end
  if keymaps.new_scratchpad then map('n', keymaps.new_scratchpad, ':PKMNewScratchpad<CR>', { desc = "New scratchpad" }) end
  if keymaps.quick_capture then map('n', keymaps.quick_capture, ':PKMQuickCapture<CR>', { desc = "Quick capture" }) end
  if keymaps.convert_note then map('n', keymaps.convert_note, ':PKMConvertNote<CR>', { desc = "Convert note type" }) end
  if keymaps.insert_citation then map('n', keymaps.insert_citation, ':PKMInsertCitation<CR>', { desc = "Insert citation" }) end
  if keymaps.goto_citation then map('n', keymaps.goto_citation, ':PKMGotoCitation<CR>', { desc = "Go to citation" }) end
  if keymaps.preview_citation then map('n', keymaps.preview_citation, ':PKMShowCitationPreview<CR>', { desc = "Preview citation" }) end
  if keymaps.link_note then map('n', keymaps.link_note, ':PKMLinkNote<CR>', { desc = "Link note" }) end
  if keymaps.follow_link then map('n', keymaps.follow_link, ':PKMFollowLink<CR>', { desc = "Follow link" }) end
  if keymaps.backlinks then map('n', keymaps.backlinks, ':PKMBacklinks<CR>', { desc = "Show backlinks" }) end
  if keymaps.search then map('n', keymaps.search, ':PKMSearch<CR>', { desc = "Search notes" }) end
  if keymaps.browse_tags then map('n', keymaps.browse_tags, ':PKMBrowseTags<CR>', { desc = "Browse tags" }) end
  if keymaps.recent_journals then map('n', keymaps.recent_journals, ':PKMRecentJournals<CR>', { desc = "Recent journals" }) end
  if keymaps.delete_note then map('n', keymaps.delete_note, ':PKMDeleteNote<CR>', { desc = "Delete note safely" }) end
end

--- Setup autocmds for bidirectional filename-YAML sync
function M.setup_sync_autocmds()
  local augroup = vim.api.nvim_create_augroup("PKMSync", { clear = true })
  
  -- Sync on save (includes reference updates)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      
      -- Only process PKM files
      if not filepath:find(M.config.root_path, 1, true) then
        return
      end
      
      -- ============================ START OF FINAL FIX ============================
      -- Schedule the ENTIRE block of post-save logic to run on the next event loop tick.
      -- This completely decouples our logic from the save event, preventing all race conditions.
      vim.schedule(function()
        -- STEP 1: Update the timestamp on disk first.
        local lines = vim.fn.readfile(filepath)
        local frontmatter, content_start = yaml.parse_frontmatter(lines)
        
        if frontmatter then
          frontmatter.last_updated_on = timestamp.to_iso8601()
          yaml.save_frontmatter(frontmatter, content_start, filepath)
        end
        
        -- STEP 2: Sync the filename. This might reload the buffer.
        if filepath:find(M.config.folders.consolidated, 1, true) then
          notes.sync_filename_on_save()
        end
        if filepath:find(M.config.folders.journal, 1, true) then
          journal.sync_filename_on_save()
        end

        -- STEP 3: Sync references. This now runs on the correct, potentially reloaded buffer.
        if M.config.sync.auto_sync_on_save then
          citations.update_references()
        end

        -- STEP 4: Tell Neovim to check for external changes. 'autoread' will handle the reload.
        -- This is now the VERY LAST step, ensuring all disk changes are complete.
        vim.cmd("checktime")
      end)
      -- ============================= END OF FINAL FIX =============================
    end,
    desc = "PKM: Auto-sync on save"
  })
  
  -- Sync YAML when file is renamed externally (This part is unchanged)
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup,
    pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      if not filepath:find(M.config.root_path, 1, true) then return end
      if filepath:find(M.config.folders.consolidated, 1, true) then notes.sync_yaml_on_rename() end
      if filepath:find(M.config.folders.journal, 1, true) then journal.sync_yaml_on_rename() end
    end,
    desc = "PKM: Sync YAML when file is renamed"
  })
end

--- Setup autocmds without auto-sync
function M.setup_basic_sync_autocmds()
  local augroup = vim.api.nvim_create_augroup("PKMSync", { clear = true })
  
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      if not filepath:find(M.config.root_path, 1, true) then return end
      
      yaml.update_last_modified()
      
      if filepath:find(M.config.folders.consolidated, 1, true) then notes.sync_filename_on_save() end
      if filepath:find(M.config.folders.journal, 1, true) then journal.sync_filename_on_save() end
    end,
    desc = "PKM: Basic sync on save (no auto-update)"
  })
end

--- Delete note safely
function M.delete_note_safely()
  local filepath = vim.fn.expand("%:p")
  if filepath == "" or not filepath:find(M.config.root_path, 1, true) then
    vim.notify("Not a valid PKM note.", vim.log.levels.ERROR)
    return
  end
  
  local filename = vim.fn.fnamemodify(filepath, ":t")
  vim.fn.inputsave()
  local confirm = vim.fn.input(string.format("Delete '%s' and all references? (yes/no): ", filename))
  vim.fn.inputrestore()
  
  if confirm:lower() ~= "yes" then
    vim.notify("Deletion cancelled.", vim.log.levels.INFO)
    return
  end
  
  citations.cleanup_deleted_note(filepath)
  vim.cmd("bdelete!")
  
  if vim.fn.delete(filepath) == 0 then
    vim.notify("Note deleted and references cleaned up.", vim.log.levels.INFO)
  else
    vim.notify("Failed to delete file.", vim.log.levels.ERROR)
  end
end

--- Show PKM statistics
function M.show_stats()
  local stats = {
    total_notes = 0, total_journals = 0, total_scratchpads = 0,
    total_citations = 0, notes_by_status = {}, notes_by_tag = {},
  }
  
  local function collect_from_folder(folder_path, note_type)
    local files = vim.fn.glob(folder_path .. "/*.md", false, true)
    
    for _, file in ipairs(files) do
      if note_type == "journal" then stats.total_journals = stats.total_journals + 1
      elseif note_type == "scratchpad" then stats.total_scratchpads = stats.total_scratchpads + 1
      else
        stats.total_notes = stats.total_notes + 1
        local content = vim.fn.readfile(file)
        local frontmatter, _ = yaml.parse_frontmatter(content)
        if frontmatter then
          local status = frontmatter.status or "unknown"
          stats.notes_by_status[status] = (stats.notes_by_status[status] or 0) + 1
          if frontmatter.tags and type(frontmatter.tags) == 'table' then
            for _, tag in ipairs(frontmatter.tags) do
              stats.notes_by_tag[tag] = (stats.notes_by_tag[tag] or 0) + 1
            end
          end
          if frontmatter.cites then
             if frontmatter.cites.notes then stats.total_citations = stats.total_citations + #frontmatter.cites.notes end
             if frontmatter.cites.bib then stats.total_citations = stats.total_citations + #frontmatter.cites.bib end
          end
        end
      end
    end
  end
  
  local root = M.config.root_path
  local path_sep = package.config:sub(1, 1)
  collect_from_folder(root .. path_sep .. M.config.folders.consolidated, "note")
  collect_from_folder(root .. path_sep .. M.config.folders.journal, "journal")
  collect_from_folder(root .. path_sep .. M.config.folders.scratchpad, "scratchpad")
  
  ui.show_stats_window(stats)
end

-- Export submodules for advanced users
M.yaml = function() return yaml or require('pkm.yaml') end
M.timestamp = function() return timestamp or require('pkm.timestamp') end
M.citations = function() return citations or require('pkm.citations') end
M.notes = function() return notes or require('pkm.notes') end
M.journal = function() return journal or require('pkm.journal') end
M.ui = function() return ui or require('pkm.ui') end

return M
```

## ./journal.lua
```lua
-- lua/pkm/journal.lua
-- Enhanced journal management with timestamp-filename bidirectional sync
-- FIXED: Remove duplicate date header, auto-use current time by default

local M = {}
local config = {}
local yaml = nil
local timestamp = nil
local path_sep = package.config:sub(1, 1)

function M.setup(user_config)
  config = user_config
  yaml = require('pkm.yaml')
  timestamp = require('pkm.timestamp')
end

--- Cross-platform path joining
local function join_path(...)
  local parts = {...}
  return table.concat(parts, path_sep)
end

--- Ensure directory exists
local function ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    return vim.fn.mkdir(path, "p") == 1
  end
  return true
end

--- Create a new journal entry
--- FIXED: Default to current time, removed duplicate markdown header
--- @param use_current boolean|nil Use current time (default: true)
function M.create_entry(use_current)
  if use_current == nil then
    use_current = true
  end
  
  local ts
  
  if use_current then
    ts = timestamp.now()
  else
    ts = timestamp.create_interactive()
    
    if not ts then
      vim.notify("Journal entry cancelled", vim.log.levels.INFO)
      return nil
    end
  end
  
  -- Generate filename
  local filename = timestamp.create_filename("journal", ts, ".md")
  
  local journal_path = join_path(config.root_path, config.folders.journal)
  ensure_dir(journal_path)
  
  local filepath = join_path(journal_path, filename)
  
  -- Check if file exists
  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("Journal entry already exists, opening...", vim.log.levels.INFO)
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
    return filepath
  end

  local fm_data = {}
  
  -- Optional fields for custom time
  if not use_current then
    vim.fn.inputsave()
    local add_tags = vim.fn.input("Add tags? (y/n): ", "n")
    vim.fn.inputrestore()
    
    if add_tags:lower() == "y" then
      vim.fn.inputsave()
      local tags_input = vim.fn.input("Tags (comma-separated): ")
      vim.fn.inputrestore()
      
      if tags_input and tags_input ~= "" then
        local tags = {}
        for tag in tags_input:gmatch("[^,]+") do
          table.insert(tags, tag:match("^%s*(.-)%s*$"))
        end
        fm_data.tags = tags
      end
    end
    
    vim.fn.inputsave()
    local add_location = vim.fn.input("Add location? (y/n): ", "n")
    vim.fn.inputrestore()
    
    if add_location:lower() == "y" then
      vim.fn.inputsave()
      local location = vim.fn.input("Location: ")
      vim.fn.inputrestore()
      
      if location and location ~= "" then
        fm_data.location = location
      end
    end
  end
  
  -- Create frontmatter, passing any interactively collected data
  local frontmatter_lines = yaml.create_frontmatter("journal", fm_data)
  
  -- Add a blank line for content
  table.insert(frontmatter_lines, "")
  
  -- Write file
  vim.fn.writefile(frontmatter_lines, filepath)
  
  -- Open file
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  
  -- Move cursor to content area
  vim.cmd("normal! G")
  vim.cmd("startinsert")
  
  vim.notify("Created journal entry: " .. filename, vim.log.levels.INFO)
  return filepath
end

--- Create journal with custom time (explicit command)
function M.create_entry_custom()
  return M.create_entry(false)
end

--- Rename journal file based on the YAML created_on timestamp
--- @param filepath string Current file path
--- @param iso_timestamp string The ISO8601 timestamp from the YAML
--- @return string|nil New filepath if renamed
function M.rename_from_yaml(filepath, iso_timestamp)
  local dir = vim.fn.fnamemodify(filepath, ":h")

  -- Convert ISO timestamp to filename format
  local new_timestamp_part = iso_timestamp:gsub("T", "_"):gsub(":", "-")
  
  local new_filename = "journal_" .. new_timestamp_part .. ".md"
  local new_filepath = join_path(dir, new_filename)
  
  -- ============================ START OF FIX ============================
  -- Normalize path separators to prevent comparison errors
  local normalized_new = new_filepath:gsub("\\", "/")
  local normalized_current = filepath:gsub("\\", "/")

  if normalized_new == normalized_current then
    return nil -- No change needed
  end
  -- ============================= END OF FIX =============================
  
  if vim.fn.filereadable(new_filepath) == 1 then
    vim.notify("Cannot rename: file already exists: " .. new_filename, vim.log.levels.ERROR)
    return nil
  end
  
  if vim.fn.rename(filepath, new_filepath) == 0 then
    vim.cmd("file " .. vim.fn.fnameescape(new_filepath))
    vim.notify("Renamed to: " .. new_filename, vim.log.levels.INFO)
    
    local old_basename = vim.fn.fnamemodify(filepath, ":t:r")
    local new_basename = vim.fn.fnamemodify(new_filepath, ":t:r")
    local new_title = "Journal " .. iso_timestamp:sub(1, 10) -- Extracts "YYYY-MM-DD"
    require('pkm.citations').update_references_on_rename(old_basename, new_basename, new_title)
    
    return new_filepath
  else
    vim.notify("Failed to rename file", vim.log.levels.ERROR)
    return nil
  end
end

--- Sync filename when timestamp in YAML changes
function M.sync_filename_on_save()
  local filepath = vim.fn.expand("%:p")
  
  -- Only process journal files
  if not filepath:find(config.folders.journal, 1, true) then
    return
  end
  
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, _ = yaml.parse_frontmatter(lines)
  
  if not frontmatter or not frontmatter.created_on then
    return
  end
  
  -- Call rename_from_yaml using the single created_on timestamp
  M.rename_from_yaml(filepath, frontmatter.created_on)
end

--- Update YAML timestamp when file is renamed externally
function M.sync_yaml_on_rename()
  local filepath = vim.fn.expand("%:p")
  
  -- Only process journal files
  if not filepath:find(config.folders.journal, 1, true) then
    return
  end
  
  local filename = vim.fn.fnamemodify(filepath, ":t:r")
  local _, timestamp_str = filename:match("^(.+)_(.+)$")
  
  if not timestamp_str then
    return
  end
  
  -- Parse timestamp from filename
  local ts = timestamp.parse_timestamp(timestamp_str)
  if not ts then
    return
  end
  
  -- Update YAML
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, content_start = yaml.parse_frontmatter(lines)
  
  if not frontmatter then
    return
  end
  
  local file_date = timestamp.format_timestamp(ts, "date_only")
  local file_time = nil
  if ts.hour then
    if ts.sec then
      file_time = string.format("%02d-%02d-%02d", ts.hour, ts.min, ts.sec)
    else
      file_time = string.format("%02d-%02d", ts.hour, ts.min)
    end
  end
  
  -- Check if update needed
  local yaml_changed = false
  if frontmatter.date ~= file_date then
    frontmatter.date = file_date
    yaml_changed = true
  end
  
  if file_time and frontmatter.time ~= file_time then
    frontmatter.time = file_time
    yaml_changed = true
  end
  
  if yaml_changed then
    yaml.save_frontmatter(frontmatter, content_start)
    vim.notify("Updated timestamp in YAML to match filename", vim.log.levels.INFO)
  end
end

--- Find journal entries by date range
--- @param start_date table Start timestamp
--- @param end_date table End timestamp
--- @return table Array of journal entries
function M.find_by_date_range(start_date, end_date)
  local journal_path = join_path(config.root_path, config.folders.journal)
  local files = vim.fn.glob(journal_path .. path_sep .. "journal_*.md", false, true)
  
  local entries = {}
  
  for _, file in ipairs(files) do
    local filename = vim.fn.fnamemodify(file, ":t:r")
    local _, ts_str = filename:match("^(.+)_(.+)$")
    
    if ts_str then
      local ts = timestamp.parse_timestamp(ts_str)
      
      if ts then
        local in_range = true
        
        if start_date then
          if timestamp.compare(ts, start_date) < 0 then
            in_range = false
          end
        end
        
        if end_date then
          if timestamp.compare(ts, end_date) > 0 then
            in_range = false
          end
        end
        
        if in_range then
          table.insert(entries, {
            path = file,
            timestamp = ts,
            display = timestamp.to_human(ts),
          })
        end
      end
    end
  end
  
  -- Sort by timestamp (newest first)
  table.sort(entries, function(a, b)
    return timestamp.compare(a.timestamp, b.timestamp) > 0
  end)
  
  return entries
end

--- List recent journal entries
--- @param count number Number of entries to return
function M.list_recent(count)
  count = count or 10
  
  local journal_path = join_path(config.root_path, config.folders.journal)
  local files = vim.fn.glob(journal_path .. path_sep .. "journal_*.md", false, true)
  
  local entries = {}
  
  for _, file in ipairs(files) do
    local filename = vim.fn.fnamemodify(file, ":t:r")
    local _, ts_str = filename:match("^(.+)_(.+)$")
    
    if ts_str then
      local ts = timestamp.parse_timestamp(ts_str)
      
      if ts then
        table.insert(entries, {
          path = file,
          timestamp = ts,
          display = timestamp.to_human(ts),
        })
      end
    end
  end
  
  -- Sort by timestamp (newest first)
  table.sort(entries, function(a, b)
    return timestamp.compare(a.timestamp, b.timestamp) > 0
  end)
  
  -- Limit to count
  local recent = {}
  for i = 1, math.min(count, #entries) do
    table.insert(recent, entries[i])
  end
  
  -- Show selector
  if #recent == 0 then
    vim.notify("No journal entries found", vim.log.levels.INFO)
    return
  end
  
  vim.ui.select(recent, {
    prompt = "Recent journal entries:",
    format_item = function(item) return item.display end,
  }, function(selected)
    if selected then
      vim.cmd("edit " .. vim.fn.fnameescape(selected.path))
    end
  end)
end

--- Find journal entries by tag
--- @param tag string Tag to search for
--- @return table Array of entries
function M.find_by_tag(tag)
  local journal_path = join_path(config.root_path, config.folders.journal)
  local files = vim.fn.glob(journal_path .. path_sep .. "journal_*.md", false, true)
  
  local entries = {}
  
  for _, file in ipairs(files) do
    local content = vim.fn.readfile(file)
    local frontmatter, _ = yaml.parse_frontmatter(content)
    
    if frontmatter and frontmatter.tags then
      for _, entry_tag in ipairs(frontmatter.tags) do
        if entry_tag:lower() == tag:lower() then
          local filename = vim.fn.fnamemodify(file, ":t:r")
          local _, ts_str = filename:match("^(.+)_(.+)$")
          local ts = ts_str and timestamp.parse_timestamp(ts_str)
          
          table.insert(entries, {
            path = file,
            timestamp = ts,
            display = ts and timestamp.to_human(ts) or filename,
          })
          break
        end
      end
    end
  end
  
  -- Sort by timestamp (newest first)
  if #entries > 0 and entries[1].timestamp then
    table.sort(entries, function(a, b)
      return timestamp.compare(a.timestamp, b.timestamp) > 0
    end)
  end
  
  return entries
end

--- Get all tags from journal entries
--- @return table Map of tag -> count
function M.get_all_tags()
  local journal_path = join_path(config.root_path, config.folders.journal)
  local files = vim.fn.glob(journal_path .. path_sep .. "journal_*.md", false, true)
  
  local tag_counts = {}
  
  for _, file in ipairs(files) do
    local content = vim.fn.readfile(file)
    local frontmatter, _ = yaml.parse_frontmatter(content)
    
    if frontmatter and frontmatter.tags then
      for _, tag in ipairs(frontmatter.tags) do
        tag_counts[tag] = (tag_counts[tag] or 0) + 1
      end
    end
  end
  
  return tag_counts
end

return M
```

## ./notes.lua
```lua
-- lua/pkm/notes.lua
-- Enhanced note management with unnamed notes and bidirectional filename-YAML sync

local M = {}
local config = {}
local yaml = nil
local timestamp = nil
local path_sep = package.config:sub(1, 1)

function M.setup(user_config)
  config = user_config
  yaml = require('pkm.yaml')
  timestamp = require('pkm.timestamp')
end

--- Cross-platform path joining
local function join_path(...)
  local parts = {...}
  return table.concat(parts, path_sep)
end

--- Ensure directory exists
local function ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    return vim.fn.mkdir(path, "p") == 1
  end
  return true
end

--- Get next available note number
local function get_next_note_number()
  local consolidated_path = join_path(config.root_path, config.folders.consolidated)
  local files = vim.fn.glob(consolidated_path .. path_sep .. "*.md", false, true)
  
  local max_num = 0
  for _, file in ipairs(files) do
    local basename = vim.fn.fnamemodify(file, ":t:r")
    local num = basename:match("^(%d+)_")
    if num then
      max_num = math.max(max_num, tonumber(num))
    end
  end
  
  return max_num + 1
end

--- Sanitize title for filename
--- @param title string Title to sanitize
--- @return string Safe filename part
local function sanitize_title(title)
  if not title or title == "" then
    return "unnamed"
  end
  
  -- Remove or replace problematic characters
  local safe = title
    :gsub("%s+", "_")                    -- spaces to underscores
    :gsub('[<>:"/\\|?*]', "")            -- remove Windows/Unix forbidden chars
    :gsub("_+", "_")                     -- collapse multiple underscores
    :gsub("^_", "")                      -- remove leading underscore
    :gsub("_$", "")                      -- remove trailing underscore
  
  if safe == "" then
    return "unnamed"
  end
  
  return safe
end

--- Create a new consolidated note
--- @param note_type string|nil Type: "agg", "note", or "bib" (nil = prompt)
--- @return string|nil Path to created note
function M.create_new_note(note_type) -- REMOVED the 'allow_unnamed' parameter
  if note_type == "" then
    note_type = nil
  end
  
  -- If no type provided, prompt for it
  if not note_type then
    vim.ui.select(
      {"note", "agg", "bib"},
      {
        prompt = "Select note type:",
        format_item = function(item)
          if item == "note" then return "Regular Note"
          elseif item == "agg" then return "Aggregate/Collection"
          elseif item == "bib" then return "Bibliography Entry"
          end
        end
      },
      function(selected)
        if selected then
          M.create_new_note(selected) -- SIMPLIFIED recursive call
        else
          vim.notify("Note creation cancelled", vim.log.levels.INFO)
        end
      end
    )
    return nil
  end
  
  -- Validate type
  if not (note_type == "agg" or note_type == "note" or note_type == "bib") then
    vim.notify("Invalid note type. Use: agg, note, or bib", vim.log.levels.ERROR)
    return nil
  end
  
  -- Get note title
  vim.fn.inputsave()
  -- SIMPLIFIED: Always allow unnamed notes
  local title = vim.fn.input("Note title (leave empty for unnamed): ")
  vim.fn.inputrestore()
  
  -- If user cancels with <Esc>, title will be nil
  if title == nil then
    vim.notify("Note creation cancelled", vim.log.levels.INFO)
    return nil
  end
  
  -- Generate filename (the rest of the function is the same)
  local note_number = get_next_note_number()
  local safe_title = sanitize_title(title)
  local filename = string.format("%04d_%s_%s.md", note_number, note_type, safe_title)
  
  local consolidated_path = join_path(config.root_path, config.folders.consolidated)
  ensure_dir(consolidated_path)
  
  local filepath = join_path(consolidated_path, filename)
  
  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("File already exists: " .. filename, vim.log.levels.ERROR)
    return nil
  end
  
  local fm_type = (note_type == "bib") and "bibliography" or "consolidated"
  local frontmatter_data = {
    title = title ~= "" and title or "Unnamed Note",
  }
  
  if note_type == "bib" then
    vim.fn.inputsave()
    local author = vim.fn.input("Author: ")
    vim.fn.inputrestore()
    if author ~= "" then
      frontmatter_data.source_author = author
    end
    
    vim.fn.inputsave()
    local source_type = vim.fn.input("Source type [book]: ", "book")
    vim.fn.inputrestore()
    frontmatter_data.source_type = source_type
  end
  
  local frontmatter_lines = yaml.create_frontmatter(fm_type, frontmatter_data)
  
  table.insert(frontmatter_lines, "")
  table.insert(frontmatter_lines, "")
  
  vim.fn.writefile(frontmatter_lines, filepath)
  
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  
  vim.cmd("normal! G")
  vim.cmd("startinsert")
  
  vim.notify("Created: " .. filename, vim.log.levels.INFO)
  return filepath
end

--- Normalize path for comparison (cross-platform)
--- @param path string Path to normalize
--- @return string Normalized absolute path with forward slashes
local function normalize_path(path)
  -- Convert to absolute path and normalize separators
  return vim.fn.fnamemodify(path, ":p"):gsub("\\", "/")
end

--- Rename file based on YAML metadata
--- @param filepath string Current file path
--- @param new_title string New title from YAML
--- @return string|nil New filepath if renamed, nil if not
function M.rename_from_yaml(filepath, new_title)
  local old_filename_no_ext = vim.fn.fnamemodify(filepath, ":t:r")
  local dir = vim.fn.fnamemodify(filepath, ":h")
  
  local number, note_type, old_title = old_filename_no_ext:match("^(%d+)_([a-z]+)_(.+)$")
  if not number or not note_type then
    return nil -- Not a valid consolidated note
  end
  
  local safe_title = sanitize_title(new_title)
  local new_filename = string.format("%04d_%s_%s.md", tonumber(number), note_type, safe_title)
  local new_filepath = join_path(dir, new_filename)
  
  -- ============================ START OF FIX ============================
  -- Normalize path separators to prevent comparison errors
  local normalized_new = new_filepath:gsub("\\", "/")
  local normalized_current = filepath:gsub("\\", "/")

  if normalized_new == normalized_current then
    return nil -- No change needed
  end
  -- ============================= END OF FIX =============================
  
  if vim.fn.filereadable(new_filepath) == 1 then
    vim.notify("Cannot rename: file already exists: " .. new_filename, vim.log.levels.ERROR)
    return nil
  end
  
  if vim.fn.rename(filepath, new_filepath) == 0 then
    vim.cmd("file " .. vim.fn.fnameescape(new_filepath))
    vim.notify("Renamed to: " .. new_filename, vim.log.levels.INFO)
    
    local new_filename_no_ext = vim.fn.fnamemodify(new_filepath, ":t:r")
    require('pkm.citations').update_references_on_rename(old_filename_no_ext, new_filename_no_ext, new_title)
    
    return new_filepath
  else
    vim.notify("Failed to rename file", vim.log.levels.ERROR)
    return nil
  end
end
--- Check and sync filename with YAML on save
function M.sync_filename_on_save()
  local filepath = vim.fn.expand("%:p")
  
  -- Only process files in consolidated folder
  if not filepath:find(config.folders.consolidated, 1, true) then
    return
  end
  
  -- Read frontmatter
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, _ = yaml.parse_frontmatter(lines)
  
  if not frontmatter or not frontmatter.title then
    return
  end
  
  -- Rename if title changed
  M.rename_from_yaml(filepath, frontmatter.title)
end

--- Update YAML when file is renamed externally
function M.sync_yaml_on_rename()
  local filepath = vim.fn.expand("%:p")
  
  -- Only process consolidated notes
  if not filepath:find(config.folders.consolidated, 1, true) then
    return
  end
  
  local filename = vim.fn.fnamemodify(filepath, ":t:r")
  local _, _, name_part = filename:match("^(%d+)_([a-z]+)_(.+)$")
  
  if not name_part then
    return
  end
  
  -- Convert filename to readable title
  local title = name_part:gsub("_", " ")
  
  -- Update YAML
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, content_start = yaml.parse_frontmatter(lines)
  
  if frontmatter and frontmatter.title ~= title then
    frontmatter.title = title
    yaml.save_frontmatter(frontmatter, content_start)
    vim.notify("Updated title in YAML to match filename", vim.log.levels.INFO)
  end
end

--- Create a scratchpad note (FIXED VERSION)
--- @return string|nil Path to created scratchpad
function M.create_scratchpad()
  local ts = timestamp.now()  -- Uses default format
  local filename = timestamp.create_filename("scratch", ts, ".md")
  
  local scratchpad_path = join_path(config.root_path, config.folders.scratchpad)
  ensure_dir(scratchpad_path)
  
  local filepath = join_path(scratchpad_path, filename)
  
  -- Create frontmatter for scratchpad with proper timestamps
  local frontmatter_lines = yaml.create_frontmatter("scratchpad", {})
  
  -- Add blank content lines
  table.insert(frontmatter_lines, "")
  
  -- Write file
  vim.fn.writefile(frontmatter_lines, filepath)
  
  -- Open file
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  
  -- Move cursor to end
  vim.cmd("normal! G")
  vim.cmd("startinsert")
  
  vim.notify("Created scratchpad: " .. filename, vim.log.levels.INFO)
  return filepath
end

--- Convert current note to different type
function M.convert_note()
  local current_path = vim.fn.expand("%:p")
  
  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end
  
  -- Determine current note type
  local current_type = nil
  
  if current_path:find(config.folders.scratchpad, 1, true) then
    current_type = "scratchpad"
  elseif current_path:find(config.folders.journal, 1, true) then
    current_type = "journal"
  elseif current_path:find(config.folders.consolidated, 1, true) then
    current_type = "consolidated"
  else
    vim.notify("Unknown note type", vim.log.levels.ERROR)
    return
  end
  
  -- Determine valid conversion targets
  local targets = {}
  if current_type == "scratchpad" then
    targets = {"journal", "note", "cancel"}
  elseif current_type == "journal" then
    targets = {"note", "cancel"}
  elseif current_type == "consolidated" then
    targets = {"journal", "cancel"}
  end
  
  -- Prompt for target type
  vim.ui.select(targets, {
    prompt = string.format("Convert %s to:", current_type),
    format_item = function(item)
      if item == "journal" then
        return "Journal Entry"
      elseif item == "note" then
        return "Consolidated Note"
      elseif item == "cancel" then
        return "Cancel"
      end
      return item
    end
  }, function(target)
    if not target or target == "cancel" then
      vim.notify("Conversion cancelled", vim.log.levels.INFO)
      return
    end
    
    M.do_convert(current_path, current_type, target)
  end)
end


--- Quick capture - Open today's scratchpad or create new
function M.quick_capture()
  local today = timestamp.now()
  local date_str = timestamp.format_timestamp(today, "date_only")
  
  local scratchpad_path = join_path(config.root_path, config.folders.scratchpad)
  local pattern = join_path(scratchpad_path, "scratch_" .. date_str .. "*.md")
  local files = vim.fn.glob(pattern, false, true)
  
  local filepath
  if #files > 0 then
    -- Use most recent scratchpad from today
    table.sort(files)
    filepath = files[#files]
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
    vim.cmd("normal! G")
  else
    filepath = M.create_scratchpad()
  end
  
  -- Add timestamp marker
  local ts = timestamp.now()
  local time_marker = "## " .. timestamp.to_human(ts)
  
  vim.api.nvim_buf_set_lines(0, -1, -1, false, {"", time_marker, ""})
  vim.cmd("normal! G")
  vim.cmd("startinsert")
  
  return filepath
end

--- Perform the actual conversion
--- @param current_path string Current file path
--- @param current_type string Current note type
--- @param target string Target note type
function M.do_convert(current_path, current_type, target)
  -- Read current content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  
  -- Parse existing frontmatter
  local existing_fm, content_start = yaml.parse_frontmatter(lines)
  
  -- Get content without frontmatter
  local content = {}
  for i = content_start, #lines do
    table.insert(content, lines[i])
  end
  
  -- Create new file based on target type
  local new_path
  
  if target == "journal" then
    local ts = timestamp.now()
    
    local journal_filename = timestamp.create_filename("journal", ts, ".md")
    local journal_path = join_path(config.root_path, config.folders.journal)
    ensure_dir(journal_path)
    new_path = join_path(journal_path, journal_filename)
    
    local fm_data = {
      date = timestamp.format_timestamp(ts, "date_only"),
      time = string.format("%02d-%02d-%02d", ts.hour, ts.min, ts.sec or 0),
    }
    
    if existing_fm and existing_fm.tags then
      fm_data.tags = existing_fm.tags
    end
    
    local new_frontmatter = yaml.create_frontmatter("journal", fm_data)
    local new_content = vim.list_extend(new_frontmatter, content)
    
    vim.fn.writefile(new_content, new_path)
    
  elseif target == "note" then
    vim.fn.inputsave()
    local title = vim.fn.input("Note title (leave empty for unnamed): ")
    vim.fn.inputrestore()
    
    local note_number = get_next_note_number()
    local safe_title = sanitize_title(title)
    local note_filename = string.format("%04d_note_%s.md", note_number, safe_title)
    
    local consolidated_path = join_path(config.root_path, config.folders.consolidated)
    ensure_dir(consolidated_path)
    new_path = join_path(consolidated_path, note_filename)
    
    local fm_data = {
      title = title ~= "" and title or "Unnamed Note",
    }
    
    if existing_fm then
      if existing_fm.tags then fm_data.tags = existing_fm.tags end
      if existing_fm.author then fm_data.author = existing_fm.author end
    end
    
    local new_frontmatter = yaml.create_frontmatter("consolidated", fm_data)
    local new_content = vim.list_extend(new_frontmatter, content)
    
    vim.fn.writefile(new_content, new_path)
  end
  
  -- Ask whether to delete original
  vim.fn.inputsave()
  local delete_original = vim.fn.input("Delete original? (y/n): ", "n")
  vim.fn.inputrestore()
  
  if delete_original:lower() == "y" then
    vim.fn.delete(current_path)
  end
  
  -- Open new file
  vim.cmd("edit " .. vim.fn.fnameescape(new_path))
  
  vim.notify("Converted to " .. target, vim.log.levels.INFO)
end

--- Link to another note
function M.link_to_note()
  local source_path = vim.fn.expand("%:p")
  if source_path == "" then
    vim.notify("Cannot link from unnamed buffer", vim.log.levels.WARN)
    return
  end
  
  -- Get all notes
  local consolidated_path = join_path(config.root_path, config.folders.consolidated)
  local files = vim.fn.glob(consolidated_path .. path_sep .. "*.md", false, true)
  
  local notes = {}
  for _, file in ipairs(files) do
    if file ~= source_path then
      local basename = vim.fn.fnamemodify(file, ":t:r")
      local number, note_type, name = basename:match("^(%d+)_([a-z]+)_(.+)$")
      
      if number and note_type and name then
        local display_name = string.format("[%s%s] %s", 
          note_type, number, name:gsub("_", " "))
        
        table.insert(notes, {
          path = file,
          display = display_name,
          basename = basename,
        })
      end
    end
  end
  
  if #notes == 0 then
    vim.notify("No notes available to link", vim.log.levels.INFO)
    return
  end
  
  vim.ui.select(notes, {
    prompt = "Link to which note?",
    format_item = function(item) return item.display end,
  }, function(selected)
    if not selected then return end
    
    local link = "[[" .. selected.basename .. "]]"
    
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local new_line = line:sub(1, col) .. link .. line:sub(col + 1)
    vim.api.nvim_set_current_line(new_line)
    
    vim.notify("Linked to: " .. selected.basename, vim.log.levels.INFO)
  end)
end

--- Follow link under cursor (FIXED VERSION)
function M.follow_link()
  local line = vim.api.nvim_get_current_line()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0)) -- col is 0-indexed
  
  -- Find all wiki-links in the line and check which one contains the cursor
  local link_target = nil
  local search_start = 1
  
  while true do
    -- Find next [[...]] link
    local link_start, link_end, content = line:find("%[%[([^%]]+)%]%]", search_start)
    
    if not link_start then
      break -- No more links found
    end
    
    -- Check if cursor is within this link (convert to 0-indexed comparison)
    -- link_start and link_end are 1-indexed from Lua string positions
    if col >= link_start - 1 and col < link_end then
      link_target = content
      break
    end
    
    -- Move search position forward
    search_start = link_end + 1
  end
  
  if not link_target then
    vim.notify("No link under cursor", vim.log.levels.WARN)
    return
  end
  
  -- Search all known folders for a file with this basename
  local potential_paths = {
    join_path(config.root_path, config.folders.consolidated, link_target .. ".md"),
    join_path(config.root_path, config.folders.journal, link_target .. ".md"),
    join_path(config.root_path, config.folders.scratchpad, link_target .. ".md"),
  }
  
  for _, target_path in ipairs(potential_paths) do
    if vim.fn.filereadable(target_path) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      vim.notify("Opened: " .. vim.fn.fnamemodify(target_path, ":t"), vim.log.levels.INFO)
      return
    end
  end
  
  vim.notify("File not found: " .. link_target .. ".md", vim.log.levels.ERROR)
end

--- Show backlinks to current note
function M.show_backlinks()
  local current_path = vim.fn.expand("%:p")
  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end
  
  local current_basename = vim.fn.fnamemodify(current_path, ":t:r")
  
  local search_paths = {
    join_path(config.root_path, config.folders.consolidated),
    join_path(config.root_path, config.folders.journal),
    join_path(config.root_path, config.folders.scratchpad),
  }
  
  local backlinks = {}
  
  for _, search_path in ipairs(search_paths) do
    local files = vim.fn.glob(search_path .. path_sep .. "*.md", false, true)
    
    for _, file in ipairs(files) do
      if file ~= current_path then
        local content = vim.fn.readfile(file)
        local has_link = false
        
        for _, line in ipairs(content) do
          if line:match("%[%[" .. vim.pesc(current_basename) .. "%]%]") then
            has_link = true
            break
          end
        end
        
        if has_link then
          table.insert(backlinks, {
            path = file,
            display = vim.fn.fnamemodify(file, ":t"),
          })
        end
      end
    end
  end
  
  if #backlinks == 0 then
    vim.notify("No backlinks found", vim.log.levels.INFO)
    return
  end
  
  vim.ui.select(backlinks, {
    prompt = "Backlinks to current note:",
    format_item = function(item) return item.display end,
  }, function(selected)
    if selected then
      vim.cmd("edit " .. vim.fn.fnameescape(selected.path))
    end
  end)
end

return M
```

## ./timestamp.lua
```lua
-- lua/pkm/timestamp.lua
-- Flexible timestamp handling for PKM system with configurable defaults

local M = {}
local config = {}

function M.setup(user_config)
  config = user_config
  
  -- Set default behavior if not specified
  config.timestamp.default_format = config.timestamp.default_format or "full"
  config.timestamp.auto_timestamp = config.timestamp.auto_timestamp ~= false -- default true
  config.timestamp.prompt_on_create = config.timestamp.prompt_on_create or false -- default false
end

--- Parse timestamp from various formats
--- @param timestamp_str string Timestamp string
--- @return table|nil Parsed timestamp {year, month, day, hour, min, sec}
function M.parse_timestamp(timestamp_str)
  if not timestamp_str then return nil end
  
  -- Try full timestamp: YYYY-MM-DD_HH-MM-SS
  local year, month, day, hour, min, sec = 
    timestamp_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)%-(%d%d)$")
  
  if year then
    return {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = tonumber(sec),
      format = "full"
    }
  end
  
  -- Try date + time without seconds: YYYY-MM-DD_HH-MM
  year, month, day, hour, min = 
    timestamp_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)$")
  
  if year then
    return {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = nil,
      format = "date_time"
    }
  end
  
  -- Try date only: YYYY-MM-DD
  year, month, day = timestamp_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  
  if year then
    return {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = nil,
      min = nil,
      sec = nil,
      format = "date_only"
    }
  end
  
  -- Try date with unknown time: YYYY-MM-DD_99-99-99
  year, month, day = 
    timestamp_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)_99%-99%-99$")
  
  if year then
    return {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = nil,
      min = nil,
      sec = nil,
      format = "date_unknown"
    }
  end
  
  return nil
end

--- Format timestamp to string
--- @param ts table Timestamp table
--- @param format_type string|nil Format type (default from config or ts.format)
--- @return string Formatted timestamp
function M.format_timestamp(ts, format_type)
  format_type = format_type or ts.format or config.timestamp.default_format
  
  if format_type == "full" then
    return string.format("%04d-%02d-%02d_%02d-%02d-%02d",
      ts.year, ts.month, ts.day, ts.hour or 0, ts.min or 0, ts.sec or 0)
  
  elseif format_type == "date_time" then
    return string.format("%04d-%02d-%02d_%02d-%02d",
      ts.year, ts.month, ts.day, ts.hour or 0, ts.min or 0)
  
  elseif format_type == "date_only" then
    return string.format("%04d-%02d-%02d",
      ts.year, ts.month, ts.day)
  
  elseif format_type == "date_unknown" then
    return string.format("%04d-%02d-%02d_%s",
      ts.year, ts.month, ts.day, config.timestamp.unknown_time_marker)
  
  else
    -- Default: use config default or full
    return M.format_timestamp(ts, config.timestamp.default_format or "full")
  end
end

--- Get current timestamp with default format
--- @param format_override string|nil Override default format
--- @return table Timestamp
function M.now(format_override)
  local date = os.date("*t")
  local format = format_override or config.timestamp.default_format or "full"
  
  local ts = {
    year = date.year,
    month = date.month,
    day = date.day,
    format = format,
  }
  
  if format == "full" then
    ts.hour = date.hour
    ts.min = date.min
    ts.sec = date.sec
  elseif format == "date_time" then
    ts.hour = date.hour
    ts.min = date.min
  elseif format == "date_unknown" then
    -- Date only with unknown marker
  elseif format == "date_only" then
    -- Date only
  end
  
  return ts
end

--- Create timestamp - uses default or prompts based on config
--- @param force_interactive boolean Force interactive mode
--- @return table|nil Timestamp or nil if cancelled
function M.create_timestamp(force_interactive)
  -- If auto timestamp enabled and not forcing interactive, return now
  if config.timestamp.auto_timestamp and not force_interactive then
    return M.now()
  end
  
  -- If prompt on create or force interactive, show interactive dialog
  if config.timestamp.prompt_on_create or force_interactive then
    return M.create_interactive()
  end
  
  -- Default: return current timestamp with default format
  return M.now()
end

--- Interactive timestamp creation (when explicitly requested)
--- @return table|nil Timestamp or nil if cancelled
function M.create_interactive()
  -- Date prompt
  vim.fn.inputsave()
  local date_str = vim.fn.input("Date (YYYY-MM-DD) [today]: ")
  vim.fn.inputrestore()
  
  local ts
  
  if date_str == "" then
    ts = M.now("date_only")
  else
    local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    
    if not year then
      vim.notify("Invalid date format", vim.log.levels.ERROR)
      return nil
    end
    
    ts = {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
    }
  end
  
  -- Time prompt
  vim.fn.inputsave()
  local time_choice = vim.fn.input(
    "Time (1=now, 2=custom, 3=unknown, 4=none) [1]: ", "1"
  )
  vim.fn.inputrestore()
  
  if time_choice == "" then time_choice = "1" end
  
  if time_choice == "1" then
    local now = os.date("*t")
    ts.hour = now.hour
    ts.min = now.min
    ts.sec = now.sec
    ts.format = "full"
    
  elseif time_choice == "2" then
    vim.fn.inputsave()
    local time_str = vim.fn.input("Time (HH:MM or HH:MM:SS): ")
    vim.fn.inputrestore()
    
    local hour, min, sec = time_str:match("^(%d%d):(%d%d):(%d%d)$")
    if hour then
      ts.hour = tonumber(hour)
      ts.min = tonumber(min)
      ts.sec = tonumber(sec)
      ts.format = "full"
    else
      hour, min = time_str:match("^(%d%d):(%d%d)$")
      if hour then
        ts.hour = tonumber(hour)
        ts.min = tonumber(min)
        ts.format = "date_time"
      else
        vim.notify("Invalid time format", vim.log.levels.ERROR)
        return nil
      end
    end
    
  elseif time_choice == "3" then
    ts.format = "date_unknown"
    
  elseif time_choice == "4" then
    ts.format = "date_only"
    
  else
    vim.notify("Invalid choice", vim.log.levels.ERROR)
    return nil
  end
  
  return ts
end

--- Get ISO 8601 formatted timestamp for YAML frontmatter
--- @param ts table|nil Timestamp (uses now if nil)
--- @return string ISO 8601 formatted string
function M.to_iso8601(ts)
  ts = ts or M.now()
  
  if ts.hour then
    return string.format("%04d-%02d-%02dT%02d:%02d:%02d",
      ts.year, ts.month, ts.day, ts.hour, ts.min, ts.sec or 0)
  else
    return string.format("%04d-%02d-%02d", ts.year, ts.month, ts.day)
  end
end

--- Convert old Google Docs timestamp format to new format
--- @param filename string Filename with timestamp
--- @return table|nil Parsed timestamp
function M.parse_legacy_filename(filename)
  local year, month, day = filename:match("(%d%d%d%d)%-(%d+)%-(%d+)")
  
  if year then
    return {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      format = "date_only"
    }
  end
  
  return nil
end

--- Create filename with timestamp
--- @param base_name string Base name for file
--- @param ts table|nil Timestamp (uses now if nil)
--- @param extension string File extension (default ".md")
--- @return string Filename
function M.create_filename(base_name, ts, extension)
  ts = ts or M.now()
  extension = extension or ".md"
  
  local timestamp_str = M.format_timestamp(ts)
  return base_name .. "_" .. timestamp_str .. extension
end

--- Parse filename with timestamp
--- @param filename string Filename
--- @return string|nil Base name
--- @return table|nil Timestamp
--- @return string|nil Extension
function M.parse_filename(filename)
  local name, ext = filename:match("^(.+)(%.%w+)$")
  if not name then
    name = filename
    ext = ""
  end
  
  local base, timestamp_str = name:match("^(.+)_(%d%d%d%d%-.+)$")
  
  if not base or not timestamp_str then
    return filename, nil, ext
  end
  
  local ts = M.parse_timestamp(timestamp_str)
  
  return base, ts, ext
end

--- Compare two timestamps
--- @param ts1 table First timestamp
--- @param ts2 table Second timestamp
--- @return number -1 if ts1 < ts2, 0 if equal, 1 if ts1 > ts2
function M.compare(ts1, ts2)
  if ts1.year ~= ts2.year then
    return ts1.year < ts2.year and -1 or 1
  end
  if ts1.month ~= ts2.month then
    return ts1.month < ts2.month and -1 or 1
  end
  if ts1.day ~= ts2.day then
    return ts1.day < ts2.day and -1 or 1
  end
  
  if not ts1.hour and not ts2.hour then
    return 0
  end
  
  if ts1.hour and not ts2.hour then
    return 1
  end
  if not ts1.hour and ts2.hour then
    return -1
  end
  
  if ts1.hour ~= ts2.hour then
    return ts1.hour < ts2.hour and -1 or 1
  end
  if ts1.min ~= ts2.min then
    return ts1.min < ts2.min and -1 or 1
  end
  
  if ts1.sec and ts2.sec then
    if ts1.sec ~= ts2.sec then
      return ts1.sec < ts2.sec and -1 or 1
    end
  end
  
  return 0
end

--- Check if timestamp is valid
--- @param ts table Timestamp
--- @return boolean True if valid
--- @return string|nil Error message if invalid
function M.validate(ts)
  if not ts.year or not ts.month or not ts.day then
    return false, "Missing date components"
  end
  
  if ts.year < 1900 or ts.year > 2100 then
    return false, "Invalid year"
  end
  
  if ts.month < 1 or ts.month > 12 then
    return false, "Invalid month"
  end
  
  if ts.day < 1 or ts.day > 31 then
    return false, "Invalid day"
  end
  
  if ts.hour then
    if ts.hour < 0 or ts.hour > 23 then
      return false, "Invalid hour"
    end
  end
  
  if ts.min then
    if ts.min < 0 or ts.min > 59 then
      return false, "Invalid minute"
    end
  end
  
  if ts.sec then
    if ts.sec < 0 or ts.sec > 59 then
      return false, "Invalid second"
    end
  end
  
  return true
end

--- Get human-readable timestamp
--- @param ts table Timestamp
--- @return string Human-readable string
function M.to_human(ts)
  local date_str = string.format("%04d-%02d-%02d", ts.year, ts.month, ts.day)
  
  if not ts.hour then
    if ts.format == "date_unknown" then
      return date_str .. " (time unknown)"
    else
      return date_str
    end
  end
  
  if ts.sec then
    return string.format("%s at %02d:%02d:%02d",
      date_str, ts.hour, ts.min, ts.sec)
  else
    return string.format("%s at %02d:%02d",
      date_str, ts.hour, ts.min)
  end
end

return M
```

## ./ui.lua
```lua
-- lua/pkm/ui.lua
-- UI components and search for PKM system

local M = {}
local config = {}
local yaml = nil
local path_sep = package.config:sub(1, 1)

function M.setup(user_config)
  config = user_config
  yaml = require('pkm.yaml')
end

--- Cross-platform path joining
local function join_path(...)
  local parts = {...}
  return table.concat(parts, path_sep)
end

--- Search all notes (Feature 5 placeholder)
--- @param query string Search query
function M.search_notes(query)
  -- Collect all markdown files
  local search_paths = {
    join_path(config.root_path, config.folders.consolidated),
    join_path(config.root_path, config.folders.journal),
    join_path(config.root_path, config.folders.scratchpad),
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
    local files = vim.fn.glob(search_path .. path_sep .. "*.md", false, true)
    
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

--- Show statistics window
--- @param stats table Statistics data
function M.show_stats_window(stats)
  -- Create buffer for stats
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  -- Build stats content
  local lines = {
    "=== PKM Statistics ===",
    "",
    "Notes:",
    string.format("  Total: %d", stats.total_notes),
    string.format("  Journals: %d", stats.total_journals),
    string.format("  Scratchpads: %d", stats.total_scratchpads),
    string.format("  Citations: %d", stats.total_citations),
    "",
    "Notes by Status:",
  }
  
  for status, count in pairs(stats.notes_by_status) do
    table.insert(lines, string.format("  %s: %d", status, count))
  end
  
  table.insert(lines, "")
  table.insert(lines, "Top Tags:")
  
  -- Sort tags by count
  local sorted_tags = {}
  for tag, count in pairs(stats.notes_by_tag) do
    table.insert(sorted_tags, {tag = tag, count = count})
  end
  table.sort(sorted_tags, function(a, b) return a.count > b.count end)
  
  for i = 1, math.min(10, #sorted_tags) do
    table.insert(lines, string.format("  %s: %d", sorted_tags[i].tag, sorted_tags[i].count))
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  -- Create floating window
  local width = 50
  local height = #lines + 2
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = 'rounded',
    title = " PKM Statistics ",
    title_pos = 'center',
  }
  
  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Close on any key
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
end

--- Tag browser (Feature 1 - for future enhancement)
--- Shows all tags and allows navigation
function M.browse_tags()
  -- Collect tags from all notes
  local all_paths = {
    join_path(config.root_path, config.folders.consolidated),
    join_path(config.root_path, config.folders.journal),
  }
  
  local tag_files = {}
  
  for _, search_path in ipairs(all_paths) do
    local files = vim.fn.glob(search_path .. path_sep .. "*.md", false, true)
    
    for _, file in ipairs(files) do
      local content = vim.fn.readfile(file)
      local frontmatter, _ = yaml.parse_frontmatter(content)
      
      if frontmatter and frontmatter.tags then
        for _, tag in ipairs(frontmatter.tags) do
          if not tag_files[tag] then
            tag_files[tag] = {}
          end
          table.insert(tag_files[tag], {
            path = file,
            filename = vim.fn.fnamemodify(file, ":t"),
          })
        end
      end
    end
  end
  
  if not next(tag_files) then
    vim.notify("No tags found", vim.log.levels.INFO)
    return
  end
  
  -- Create tag list
  local tag_list = {}
  for tag, files in pairs(tag_files) do
    table.insert(tag_list, {
      tag = tag,
      count = #files,
      files = files,
    })
  end
  
  table.sort(tag_list, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.tag < b.tag
  end)
  
  -- First selection: choose tag
  vim.ui.select(tag_list, {
    prompt = "Browse by tag:",
    format_item = function(item)
      return string.format("%s (%d)", item.tag, item.count)
    end,
  }, function(selected_tag)
    if not selected_tag then return end
    
    -- Second selection: choose file
    vim.ui.select(selected_tag.files, {
      prompt = string.format("Files tagged '%s':", selected_tag.tag),
      format_item = function(item) return item.filename end,
    }, function(selected_file)
      if selected_file then
        vim.cmd("edit " .. vim.fn.fnameescape(selected_file.path))
      end
    end)
  end)
end

--- Enhanced note selector with filtering
--- This is for integration with Telescope in the future
--- @param notes table Array of note items
--- @param prompt string Prompt text
--- @param callback function Selection callback
function M.select_note_enhanced(notes, prompt, callback)
  -- Check if Telescope is available
  local has_telescope, telescope = pcall(require, "telescope")
  
  if has_telescope then
    -- Use Telescope for enhanced selection
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    
    pickers.new({}, {
      prompt_title = prompt,
      finder = finders.new_table {
        results = notes,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.display,
          }
        end,
      },
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            callback(selection.value)
          else
            callback(nil)
          end
        end)
        return true
      end,
    }):find()
  else
    -- Fallback to vim.ui.select
    vim.ui.select(notes, {
      prompt = prompt,
      format_item = function(item) return item.display end,
    }, callback)
  end
end

--- Graph view placeholder (Feature 2 - for future implementation)
function M.show_graph()
  vim.notify("Graph view not yet implemented", vim.log.levels.INFO)
  -- This would show a visual graph of note connections
  -- Could use graphviz or similar for visualization
end

--- Analytics dashboard placeholder (Feature 8 - for future implementation)
function M.show_analytics()
  -- This would show:
  -- - Reading time estimates
  -- - Word counts per note/journal
  -- - Writing patterns (when you write most)
  -- - Connection density
  -- - Growth over time
  vim.notify("Analytics dashboard not yet implemented", vim.log.levels.INFO)
end

return M
```

## ./yaml.lua
```lua
-- lua/pkm/yaml.lua
-- YAML frontmatter handling with automatic timestamp management
-- FIXED VERSION: Resolves empty nested structure corruption

local M = {}
local config = {}
local timestamp_module = nil

function M.setup(user_config)
  config = user_config
  timestamp_module = require('pkm.timestamp')
end

--- Parse YAML frontmatter from file content
--- @param lines table Array of file lines
--- @return table|nil Parsed frontmatter, or nil if none found
--- @return number Start line of content (after frontmatter)
function M.parse_frontmatter(lines)
  if not lines or #lines == 0 then
    return nil, 1
  end
  
  if lines[1] ~= "---" then
    return nil, 1
  end
  
  local end_line = nil
  for i = 2, #lines do
    if lines[i] == "---" or lines[i] == "..." then
      end_line = i
      break
    end
  end
  
  if not end_line then
    return nil, 1
  end
  
  local yaml_lines = {}
  for i = 2, end_line - 1 do
    table.insert(yaml_lines, lines[i])
  end
  
  local frontmatter = M.parse_yaml(yaml_lines)
  
  return frontmatter, end_line + 1
end

--- Simple YAML parser for frontmatter - FIXED VERSION
--- Handles nested empty arrays AND multi-line array items
--- @param lines table Array of YAML lines
--- @return table Parsed YAML as Lua table
function M.parse_yaml(lines)
  local result = {}
  local current_key = nil
  local current_array = nil
  local indent_stack = {{key = nil, indent = -1, table = result}}
  
  for _, line in ipairs(lines) do
    -- Skip empty lines and comments
    if line:match("^%s*$") or line:match("^%s*#") then
      goto continue
    end
    
    local indent = #line:match("^%s*")
    local content = line:gsub("^%s+", "")
    
    -- Handle array items
    if content:match("^%-") then
      local value = content:match("^%-%s*(.*)")
      
      if not current_array then
        vim.notify("Array item without array context", vim.log.levels.WARN)
        goto continue
      end
      
      -- FIXED: Handle multi-line array items (object items)
      if value == "" or value:match("^%s*$") then
        -- Empty dash means the object properties follow on next lines
        -- Create a table for this array item
        local item_table = {}
        table.insert(current_array, item_table)
        
        -- Push this item onto the stack so subsequent properties go into it
        table.insert(indent_stack, {
          key = nil,  -- No key, this is an array item
          indent = indent,
          table = item_table,
          is_array_item = true  -- Mark as array item
        })
      else
        -- Simple value on same line as dash
        local parsed_value = M.parse_value(value)
        table.insert(current_array, parsed_value)
      end
      
      goto continue
    end
    
    -- Handle key-value pairs
    local key, value = content:match("^([%w_%-]+):%s*(.*)")
    
    if key then
      -- Find correct target table based on indentation
      local target_table = result
      
      -- Pop stack items that are at same or shallower level
      while #indent_stack > 1 and indent <= indent_stack[#indent_stack].indent do
        table.remove(indent_stack)
      end
      
      -- Use the current top of stack as target
      target_table = indent_stack[#indent_stack].table
      
      -- Handle explicit empty array notation []
      if value == "[]" then
        target_table[key] = {}
        current_key = nil
        current_array = nil
        
      elseif value == "" or value:match("^%s*$") then
        -- Create nested table for child elements
        local nested_table = {}
        target_table[key] = nested_table
        current_array = nested_table
        
        -- Push to stack
        table.insert(indent_stack, {
          key = key,
          indent = indent,
          table = nested_table
        })
        
      else
        target_table[key] = M.parse_value(value)
        current_key = nil
        current_array = nil
      end
    end
    
    ::continue::
  end
  
  return result
end

--- Parse a YAML value
--- @param value string Raw value string
--- @return any Parsed value
function M.parse_value(value)
  -- Handle nil or empty values first
  if not value or value == "" then
    return nil
  end
  
  -- Ensure value is a string before string operations
  if type(value) ~= "string" then
    return value
  end
  
  value = value:match("^%s*(.-)%s*$")
  
  if value == "null" or value == "~" or value == "" then
    return nil
  end
  
  if value == "true" or value == "yes" or value == "on" then
    return true
  end
  if value == "false" or value == "no" or value == "off" then
    return false
  end
  
  local num = tonumber(value)
  if num then
    return num
  end
  
  if value:match('^".-"$') then
    return value:sub(2, -2)
  end
  if value:match("^'.-'$") then
    return value:sub(2, -2)
  end
  
  return value
end

-- ============================================================================
-- FIXED: YAML GENERATION WITH PROPER EMPTY ARRAY HANDLING
-- ============================================================================

--- Check if table is completely empty
--- @param t table Table to check
--- @return boolean True if table has no entries
local function is_empty_table(t)
  return next(t) == nil
end

--- Check if table is an array (sequential numeric keys)
--- @param t table Table to check
--- @return boolean True if table is an array
local function is_array_table(t)
  -- Empty tables are treated as arrays
  if is_empty_table(t) then
    return true
  end
  
  -- Check if all keys are sequential numbers starting from 1
  local count = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then
      return false
    end
    count = count + 1
  end
  
  -- Verify sequential from 1 to count
  for i = 1, count do
    if t[i] == nil then
      return false
    end
  end
  
  return count > 0
end

--- Generate YAML frontmatter from table with a predefined key order.
--- @param data table Data to convert to YAML
--- @param indent number Current indentation level
--- @return table Array of YAML lines
function M.generate_yaml(data, indent)
  indent = indent or 0
  local lines = {}
  local indent_str = string.rep("  ", indent)

  -- 1. Define the desired logical order for keys.
  local key_order = {
    "title", "author", "source_author", "note_author", "status", "tags",
    "created_on", "last_updated_on", "cites", "cited_by", "citation",
    "source_type", "source_location"
  }
  local seen = {}

  -- Helper function to process a key-value pair
  local function process_key(key, value)
    local value_type = type(value)

    if value_type == "table" then
      -- Case 1: The table is empty.
      if next(value) == nil then
        table.insert(lines, indent_str .. key .. ": []")
        return
      end

      -- Case 2: The table is an array.
      local is_array = #value > 0 and next(value, #value) == nil
      if is_array then
        table.insert(lines, indent_str .. key .. ":")
        for _, item in ipairs(value) do
          if type(item) == "table" then
            -- Handle nested objects within an array
            local nested_lines = M.generate_yaml(item, indent + 2)
            table.insert(lines, indent_str .. "  -")
            for _, nested_line in ipairs(nested_lines) do
                table.insert(lines, "  " .. nested_line)
            end
          else
            table.insert(lines, indent_str .. "  - " .. M.format_value(item))
          end
        end
      else
        -- Case 3: The table is a dictionary/map.
        table.insert(lines, indent_str .. key .. ":")
        local nested_lines = M.generate_yaml(value, indent + 1)
        for _, nested_line in ipairs(nested_lines) do
          table.insert(lines, nested_line)
        end
      end
    else
      -- Case 4: The value is a primitive (string, number, etc.).
      table.insert(lines, indent_str .. key .. ": " .. M.format_value(value))
    end
  end

  -- 2. First pass: Iterate through our predefined order.
  for _, key in ipairs(key_order) do
    if data[key] ~= nil then
      process_key(key, data[key])
      seen[key] = true
    end
  end

  -- 3. Second pass: Iterate through any remaining keys not in our list.
  for key, value in pairs(data) do
    if not seen[key] then
      process_key(key, value)
    end
  end
  
  return lines
end

--- Format a value for YAML output
--- @param value any Value to format
--- @return string Formatted value
function M.format_value(value)
  local value_type = type(value)
  
  if value_type == "nil" then
    return "null"
  elseif value_type == "boolean" then
    return value and "true" or "false"
  elseif value_type == "number" then
    return tostring(value)
  elseif value_type == "string" then
    if value:match("^[%w_%-]+$") then
      return value
    else
      return '"' .. value:gsub('"', '\\"') .. '"'
    end
  else
    return tostring(value)
  end
end

--- Create frontmatter for a new note
--- @param note_type string Type of note
--- @param custom_data table|nil Custom frontmatter fields
--- @return table Array of frontmatter lines (including delimiters)
function M.create_frontmatter(note_type, custom_data)
  local template = vim.deepcopy(config.frontmatter_templates[note_type] or {})
  
  if custom_data then
    template = vim.tbl_deep_extend("force", template, custom_data)
  end
  
  -- Process special markers and date formats
  for key, value in pairs(template) do
    if type(value) == "string" then
      if value == "ISO8601" then
        -- Replace with current ISO 8601 timestamp
        template[key] = timestamp_module.to_iso8601()
      elseif value:match("^%%") then
        -- Old-style date format string
        template[key] = os.date(value)
      end
    end
  end
  
  local yaml_lines = M.generate_yaml(template)
  
  local lines = {"---"}
  for _, line in ipairs(yaml_lines) do
    table.insert(lines, line)
  end
  table.insert(lines, "---")
  table.insert(lines, "")
  
  return lines
end

--- Update last_updated_on field in current buffer
function M.update_last_modified()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, content_start = M.parse_frontmatter(lines)
  
  if not frontmatter then
    return -- No frontmatter, do nothing
  end
  
  local new_timestamp = timestamp_module.to_iso8601()
  
  -- Only update if the timestamp is actually different
  if frontmatter.last_updated_on ~= new_timestamp then
    frontmatter.last_updated_on = new_timestamp
    M.save_frontmatter(frontmatter, content_start)
  end
end

--- Setup autocmd to update last_updated_on on save
function M.setup_auto_update()
  vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*.md",
    callback = function()
      -- Only update if file is in PKM directories
      local filepath = vim.fn.expand("%:p")
      local root = config.root_path
      
      if filepath:find(root, 1, true) then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local frontmatter, content_start = M.parse_frontmatter(lines)
        
        if frontmatter and frontmatter.last_updated_on then
          frontmatter.last_updated_on = timestamp_module.to_iso8601()
          M.save_frontmatter(frontmatter, content_start)
        end
      end
    end,
    desc = "Auto-update last_updated_on timestamp"
  })
end

--- Update frontmatter in current buffer (interactive)
function M.update_frontmatter()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, content_start = M.parse_frontmatter(lines)
  
  if not frontmatter then
    vim.notify("No frontmatter found", vim.log.levels.WARN)
    return
  end
  
  vim.ui.input({
    prompt = "Edit frontmatter (key=value, or 'done' to finish): "
  }, function(input)
    if not input or input == "done" then
      M.save_frontmatter(frontmatter, content_start)
      return
    end
    
    local key, value = input:match("^([^=]+)=(.+)$")
    if key and value then
      key = key:gsub("^%s+", ""):gsub("%s+$", "")
      value = M.parse_value(value)
      frontmatter[key] = value
      vim.notify("Updated: " .. key .. " = " .. tostring(value), vim.log.levels.INFO)
    else
      vim.notify("Invalid format. Use: key=value", vim.log.levels.WARN)
    end
    
    vim.schedule(function()
      M.update_frontmatter()
    end)
  end)
end

--- Save updated frontmatter to the buffer or a specified file.
--- @param frontmatter table Frontmatter data
--- @param content_start number Line where content starts
--- @param filepath string|nil Optional path to a file to write to. If nil, writes to the current buffer.
function M.save_frontmatter(frontmatter, content_start, filepath)
  -- 1. Generate the new YAML text from the table
  local new_fm_lines = {"---"}
  local yaml_lines = M.generate_yaml(frontmatter)
  for _, line in ipairs(yaml_lines) do
    table.insert(new_fm_lines, line)
  end
  table.insert(new_fm_lines, "---")

  -- 2. Decide whether to write to the current buffer or a different file
  if not filepath then
    -- CASE A: No filepath provided, modify the CURRENT buffer
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    
    -- FIXED: Check if there's already a blank line after frontmatter
    -- content_start is 1-indexed, so lines[content_start] is the first content line
    local has_blank_after = (#lines >= content_start and lines[content_start] == "")
    
    -- Only add blank line if one doesn't already exist
    if not has_blank_after then
      table.insert(new_fm_lines, "")
    end
    
    vim.api.nvim_buf_set_lines(0, 0, content_start - 1, false, new_fm_lines)
    
  else
    -- CASE B: Filepath provided, read that file and replace its frontmatter
    local original_content = vim.fn.readfile(filepath)
    local final_content = {}
    
    -- Add the new frontmatter
    for _, line in ipairs(new_fm_lines) do
      table.insert(final_content, line)
    end

    -- Find where the original content started (could be different from current buffer)
    local _, original_content_start = M.parse_frontmatter(original_content)

    -- FIXED: Check if content starts with blank line
    local has_blank_after = (#original_content >= original_content_start and 
                            original_content[original_content_start] == "")
    
    -- Add a blank line if the content doesn't start with one
    if not has_blank_after then
      table.insert(final_content, "")
    end
    
    -- Append the rest of the original file's content
    for i = original_content_start, #original_content do
      table.insert(final_content, original_content[i])
    end
    
    -- Write the entire reconstructed content back to the file
    vim.fn.writefile(final_content, filepath)
  end
end

--- Validate frontmatter structure
function M.validate_frontmatter()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, _ = M.parse_frontmatter(lines)
  
  if not frontmatter then
    vim.notify("No frontmatter found", vim.log.levels.ERROR)
    return false
  end
  
  local filepath = vim.fn.expand("%:p")
  local note_type = nil
  
  for type_name, folder in pairs(config.folders) do
    if filepath:match(folder) then
      note_type = type_name == "consolidated" and "consolidated" or type_name
      break
    end
  end
  
  if not note_type then
    vim.notify("Unknown note type, cannot validate", vim.log.levels.WARN)
    return false
  end
  
  local template = config.frontmatter_templates[note_type]
  if not template then
    vim.notify("No template for this note type", vim.log.levels.INFO)
    return true
  end
  
  local missing = {}
  for key, _ in pairs(template) do
    if frontmatter[key] == nil then
      table.insert(missing, key)
    end
  end
  
  if #missing > 0 then
    vim.notify("Missing fields: " .. table.concat(missing, ", "), vim.log.levels.WARN)
    return false
  else
    vim.notify("Frontmatter valid", vim.log.levels.INFO)
    return true
  end
end

--- Add or update a field in frontmatter
--- @param key string Field key
--- @param value any Field value
function M.set_field(key, value)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, content_start = M.parse_frontmatter(lines)
  
  if not frontmatter then
    vim.notify("No frontmatter to update", vim.log.levels.ERROR)
    return
  end
  
  frontmatter[key] = value
  M.save_frontmatter(frontmatter, content_start)
end

--- Get a field from frontmatter
--- @param key string Field key
--- @return any|nil Field value
function M.get_field(key)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, _ = M.parse_frontmatter(lines)
  
  if not frontmatter then
    return nil
  end
  
  return frontmatter[key]
end

return M
```
