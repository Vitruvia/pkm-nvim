-- lua/pkm/journal.lua
-- Enhanced journal management with timestamp-filename bidirectional sync
-- FIXED: Remove duplicate date header, auto-use current time by default

local M = {}
local utils = require('pkm.utils')
local config = {}
local yaml = nil
local timestamp = nil

function M.setup(user_config)
  config = user_config
  yaml = require('pkm.yaml')
  timestamp = require('pkm.timestamp')
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
  
  local journal_path = utils.join(config.root_path, config.folders.journal)
  utils.ensure_dir(journal_path)
  
  local filepath = utils.join(journal_path, filename)
  
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
  local new_filepath = utils.join(dir, new_filename)
  
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
  local journal_path = utils.join(config.root_path, config.folders.journal)
  local files = vim.fn.glob(journal_path .. utils.sep .. "journal_*.md", false, true)
  
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
  
  local journal_path = utils.join(config.root_path, config.folders.journal)
  local files = vim.fn.glob(journal_path .. utils.sep .. "journal_*.md", false, true)
  
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
  local journal_path = utils.join(config.root_path, config.folders.journal)
  local files = vim.fn.glob(journal_path .. utils.sep .. "journal_*.md", false, true)
  
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
  local journal_path = utils.join(config.root_path, config.folders.journal)
  local files = vim.fn.glob(journal_path .. utils.sep .. "journal_*.md", false, true)
  
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
