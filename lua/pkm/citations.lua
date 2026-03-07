-- lua/pkm/citations.lua
-- FIXED VERSION: Restores get_all_tags, fixes detection, and adds cross-update delete

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

--- Helper to extract tags safely
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

-- ============================================================================
-- FIXED: Missing function restored for Telescope
-- ============================================================================
function M.get_all_tags()
  local all_tags = {}
  local search_paths = {
    config.folders.consolidated, 
    config.folders.journal, 
    config.folders.scratchpad
  }

  for _, folder in ipairs(search_paths) do
    if folder then
        local search_path = join_path(config.root_path, folder)
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
        local files = vim.fn.glob(search_path .. "/*.md", false, true)
        if type(files) ~= "table" then files = {} end

        for _, file in ipairs(files) do
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

-- Compatibility alias for Telescope
M.get_citable_items_list = M.get_citable_items_for_picker

--- Initialize or migrate cited_by to new grouped structure
local function ensure_grouped_cited_by(frontmatter)
  if not frontmatter.cited_by then
    frontmatter.cited_by = {notes = {}, bib = {}, journal = {}}
    return false
  end
  
  if frontmatter.cited_by.notes or frontmatter.cited_by.bib then
    frontmatter.cited_by.notes = frontmatter.cited_by.notes or {}
    frontmatter.cited_by.bib = frontmatter.cited_by.bib or {}
    frontmatter.cited_by.journal = frontmatter.cited_by.journal or {}
    return false
  end
  
  local old_array = frontmatter.cited_by
  local new_structure = {notes = {}, bib = {}, journal = {}}
  
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
          elseif entry.type == "journal" then
            table.insert(new_structure.journal, clean_entry)
          else
            table.insert(new_structure.notes, clean_entry)
          end
        end
      end
  end
  
  frontmatter.cited_by = new_structure
  return true
end

--- Adds or removes a backlink from a target file
local function manage_backlink(citing_path, target_path, action)
  local citing_type, citing_id = M.get_note_type_and_id(citing_path)
  if not citing_type or not citing_id then return end
  
  local target_content = vim.fn.readfile(target_path)
  local target_fm, _ = yaml.parse_frontmatter(target_content)
  if target_fm and target_fm.type == "agg" then return end
  
  local content = vim.fn.readfile(target_path)
  local fm, content_start = yaml.parse_frontmatter(content)
  if not fm then return end
  
  local migrated = ensure_grouped_cited_by(fm)
  
  local group = "notes"
  if citing_type == "bib" then group = "bib" end
  if citing_type == "journal" then group = "journal" end
  
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
      title = M.get_note_title(citing_path),
      link = "[[" .. vim.fn.fnamemodify(citing_path, ":t:r") .. "]]"
    })
    modified = true
    
  elseif action == "remove" and found_index then
    table.remove(fm.cited_by[group], found_index)
    modified = true
  end
  
  if modified then
    if fm.cited_by.notes then
        table.sort(fm.cited_by.notes, function(a, b) return (a.identifier or "") < (b.identifier or "") end)
    end
    if fm.cited_by.bib then
        table.sort(fm.cited_by.bib, function(a, b) return (a.identifier or "") < (b.identifier or "") end)
    end
    yaml.save_frontmatter(fm, content_start, target_path)
  end
end

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
  end
end

function M.update_references(target_file)
  -- 1. Determine Context (Buffer vs Disk)
  local current_path = target_file or vim.fn.expand("%:p")
  if not current_path or current_path == "" then return end
  
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
    frontmatter.cites = {notes = {}, bib = {}, journal = {}}
  elseif type(frontmatter.cites) == "table" then
    if not frontmatter.cites.notes and not frontmatter.cites.bib then
        local old_array = frontmatter.cites
        frontmatter.cites = {notes = {}, bib = {}, journal = {}}
        for _, entry in ipairs(old_array) do
          if type(entry) == "table" and entry.identifier then
            local group = "notes"
            if entry.type == "bib" then group = "bib" end
            if entry.type == "journal" then group = "journal" end
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
  local groups = {"notes", "bib", "journal"}
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
  
  local new_cites = {notes = {}, bib = {}, journal = {}}
  local new_cites_map = {}
  
-- 5. Scan Text for Citations
  for i = content_start, #lines do
    for match in lines[i]:gmatch("%w+%[[%w%-_]+%]") do
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

--- Helper to insert citation text and update refs (Used by Telescope)
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

function M.update_references_on_rename(old_basename, new_basename, new_title)
  local old_type, old_id = M.get_note_type_and_id(old_basename .. ".md")
  local new_type, new_id = nil, nil
  if new_basename ~= "__DELETED__" then
      new_type, new_id = M.get_note_type_and_id(new_basename .. ".md")
  end
  
  if not old_id then return end
  
  local search_paths = {
    config.folders.consolidated,
    config.folders.journal, 
    config.folders.scratchpad
  }
  
  for _, folder in ipairs(search_paths) do
    if folder then
        local search_path = join_path(config.root_path, folder)
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
                for _, group_key in ipairs({"notes", "bib", "journal"}) do
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
              else
                  vim.fn.writefile(new_content_lines, file)
              end
          end
        end
    end
  end
end

-- ============================================================================
-- FIXED: Cleanup deleted note - Now handles cross-updates
-- ============================================================================
function M.cleanup_deleted_note(deleted_path)
    -- 1. Get the list of notes that the deleted note cited
    -- (We need to remove the "Cited by" backlink from them)
    local content = vim.fn.readfile(deleted_path)
    local fm = yaml.parse_frontmatter(content)
    
    if fm and fm.cites then
        local items_map = M.get_citable_items_map()
        local groups = {"notes", "bib", "journal"}
        
        for _, group in ipairs(groups) do
            if fm.cites[group] then
                for _, entry in ipairs(fm.cites[group]) do
                    if entry.identifier then
                        local target = items_map[entry.identifier]
                        if target then
                             -- Force remove my backlink from the target
                             manage_backlink(deleted_path, target.path, "remove")
                        end
                    end
                end
            end
        end
    end

    -- 2. Remove references TO this deleted note from other files
    M.update_references_on_rename(
        vim.fn.fnamemodify(deleted_path, ":t:r"), 
        "__DELETED__", 
        nil
    )
end

return M
