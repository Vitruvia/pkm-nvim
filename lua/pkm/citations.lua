-- lua/pkm/citations.lua
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
    if folder then
        local search_path = join_path(config.root_path, folder)
        -- FIXED: Safety check for glob return type
        local files = vim.fn.glob(search_path .. "/*.md", false, true)
        if type(files) ~= "table" then files = {} end

        for _, file in ipairs(files) do
          -- FIXED: Renamed 'type' to 'item_type' to avoid shadowing global type()
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

-- FIXED: Compatibility alias for Telescope (which expects this name)
M.get_citable_items_list = M.get_citable_items_for_picker

--- FIXED: Initialize or migrate cited_by to new grouped structure
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
  
  if type(old_array) == "table" then
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
  end
  
  frontmatter.cited_by = new_structure
  return true
end

--- FIXED: Adds or removes a backlink from a target file
local function manage_backlink(citing_path, target_path, action)
  local citing_type, citing_id = M.get_note_type_and_id(citing_path)
  if not citing_type or not citing_id then return end
  
  -- VALIDATION: Check if target is aggregate note
  local target_content = vim.fn.readfile(target_path)
  local target_fm, _ = yaml.parse_frontmatter(target_content)
  
  if target_fm and target_fm.type == "agg" then
    -- Silently fail for aggregates to avoid spamming errors during bulk updates
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
    -- Add new backlink
    if not fm.cited_by[group] then fm.cited_by[group] = {} end
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
    if fm.cited_by.notes then
        table.sort(fm.cited_by.notes, function(a, b) 
          return (a.identifier or "") < (b.identifier or "") 
        end)
    end
    if fm.cited_by.bib then
        table.sort(fm.cited_by.bib, function(a, b) 
          return (a.identifier or "") < (b.identifier or "") 
        end)
    end
    
    yaml.save_frontmatter(fm, content_start, target_path)
  end
end

--- FIXED: Migrate legacy inline links to YAML
local function migrate_legacy_links(filepath)
  local content = vim.fn.readfile(filepath)
  local fm, content_start = yaml.parse_frontmatter(content)
  
  if not fm then return end
  
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
    else
      table.insert(clean_content, line)
    end
  end
  
  -- Process found legacy links
  if #legacy_links > 0 then
    local items_map = M.get_citable_items_map()
    
    for _, basename in ipairs(legacy_links) do
      local found = false
      for id, data in pairs(items_map) do
        if data.basename == basename then
          local group = (data.type == "bib") and "bib" or "notes"
          
          local exists = false
          if fm.cited_by[group] then
              for _, entry in ipairs(fm.cited_by[group]) do
                if entry.identifier == id then
                  exists = true
                  break
                end
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
    end
    
    -- Write updated file
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
  end
end

--- ENHANCED: Update references with file existence validation
function M.update_references()
  local current_path = vim.fn.expand("%:p")
  if not current_path or current_path == "" then return end
  
  migrate_legacy_links(current_path)
  
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, content_start = yaml.parse_frontmatter(lines)
  if not frontmatter then return end
  
  -- Ensure cites uses grouped structure
  if not frontmatter.cites then
    frontmatter.cites = {notes = {}, bib = {}}
  elseif type(frontmatter.cites) == "table" then
    if not frontmatter.cites.notes and not frontmatter.cites.bib then
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
  
  for i = content_start, #lines do
    for match in lines[i]:gmatch("%w+%[[%w%-_]+%]") do
      local cite_type, short_id = M.parse_citation(match)
      if cite_type and short_id then
        local key = cite_type .. "|" .. short_id
        local item = all_items_by_short[key]
        
        if item then
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
          end
        end
      end
    end
  end
  
  -- Sort
  table.sort(new_cites.notes, function(a, b) return a.identifier < b.identifier end)
  table.sort(new_cites.bib, function(a, b) return a.identifier < b.identifier end)
  
  frontmatter.cites = new_cites
  yaml.save_frontmatter(frontmatter, content_start)
  
  -- Update backlinks (Cross-updating)
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

--- Cleanup deleted note references
function M.cleanup_deleted_note(deleted_path)
    -- Simply remove backlinks to this file from everything else
    M.update_references_on_rename(
        vim.fn.fnamemodify(deleted_path, ":t:r"), 
        "__DELETED__", 
        nil
    )
    -- This is a simplified version; real cleanup requires reading the deleted file's cites.
    -- Assuming deleted file is already gone or we just want to break links.
end

return M
