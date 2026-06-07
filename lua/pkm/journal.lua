-- =============================================================================
-- pkm.journal — Journal entry creation, navigation, and sync
-- =============================================================================
-- Dependencies : pkm.yaml, pkm.utils, pkm.timestamp, pkm.citations (lazy)
-- Consumed by  : pkm.commands, pkm.keymaps, pkm.init (autocmds)
--
-- Public API:
--   setup(user_config)                    → Initialize with resolved PKM config
--   create_entry(use_current?)            → Create journal entry (default: now)
--   create_entry_custom()                 → Create entry with interactive timestamp
--   rename_from_yaml(filepath, iso)       → Rename file to match created_on timestamp
--   sync_filename_on_save()               → Sync filename to created_on on BufWritePost
--   sync_yaml_on_rename()                 → Sync YAML timestamp to filename on BufReadPost
--   find_by_date_range(start, end)        → Return entries within a date range
--   list_recent(count?)                   → Show picker of N most recent entries
--   find_by_tag(tag)                      → Return entries matching a tag
--   get_all_tags()                        → table<tag, count> for journal folder only
-- =============================================================================
local M = {}

local utils = require('pkm.utils')
local config = {}
local yaml = nil
local timestamp = nil

-- =============================================================================
-- SECTION: Setup
-- =============================================================================
---@param user_config table Resolved PKM config from pkm.config.resolve()
function M.setup(user_config)
  config = user_config
  yaml = require('pkm.yaml')
  timestamp = require('pkm.timestamp')
end

-- =============================================================================
-- SECTION: Entry creation
-- =============================================================================
--- Create a new journal entry. Defaults to the current time.
--- When use_current is false, prompts interactively for timestamp, tags,
--- and location. If a file already exists for the timestamp, opens it instead.
---@param use_current boolean|nil Use current time (default: true)
---@return string|nil filepath Absolute path of created or opened entry
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

--- Create a journal entry with an interactively chosen timestamp.
--- Convenience wrapper around create_entry(false).
---@return string|nil filepath
function M.create_entry_custom()
  return M.create_entry(false)
end

-- =============================================================================
-- SECTION: Filename-YAML synchronization
-- =============================================================================
--- Rename a journal file to match its created_on YAML timestamp.
--- Converts ISO8601 format to filename format (colons → dashes, T → underscore).
--- Propagates the rename through citations via update_references_on_rename.
---@param filepath string Current absolute path of the journal file
---@param iso_timestamp string ISO8601 timestamp string from created_on field
---@return string|nil new_filepath New absolute path if renamed, nil if unchanged or failed
function M.rename_from_yaml(filepath, iso_timestamp)
  local dir = vim.fn.fnamemodify(filepath, ":h")

  -- Convert ISO timestamp to filename format
  local new_timestamp_part = iso_timestamp:gsub("T", "_"):gsub(":", "-")
  
  local new_filename = "journal_" .. new_timestamp_part .. ".md"
  local new_filepath = utils.join(dir, new_filename)
  
  local normalized_new = new_filepath:gsub("\\", "/")
  local normalized_current = filepath:gsub("\\", "/")

  if normalized_new == normalized_current then
    return nil
  end
  
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

--- Called on BufWritePost. Reads created_on from the current buffer's
--- frontmatter and renames the file if the timestamp has changed.
--- Journal folder only.
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

-- =============================================================================
-- SECTION: Querying and navigation
-- =============================================================================
--- Return all journal entries whose timestamps fall within a date range.
--- Entries are sorted newest first. Either bound may be nil (open range).
---@param start_date table|nil Timestamp table (from pkm.timestamp)
---@param end_date table|nil Timestamp table (from pkm.timestamp)
---@return {path:string, timestamp:table, display:string}[]
function M.find_by_date_range(start_date, end_date)
  local journal_path = utils.join(config.root_path, config.folders.journal)
  local files = vim.fn.glob(journal_path .. utils.sep .. "journal_*.md", false, true)
  
  local entries = {}
  
  for _, file in ipairs(files) do
    local filename = vim.fn.fnamemodify(file, ":t:r")
    local ts_str = filename:match("^journal_(.+)$")
    
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

--- Show a vim.ui.select picker of the N most recent journal entries.
---@param count integer|nil Number of entries to show (default: 10)
function M.list_recent(count)
  count = count or 10
  
  local journal_path = utils.join(config.root_path, config.folders.journal)
  local files = vim.fn.glob(journal_path .. utils.sep .. "journal_*.md", false, true)
  
  local entries = {}
  
  for _, file in ipairs(files) do
    local filename = vim.fn.fnamemodify(file, ":t:r")
    local ts_str = filename:match("^journal_(.+)$")
    
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

--- Return all journal entries that carry a specific tag (case-insensitive).
--- Sorted newest first when timestamps are available.
---@param tag string Tag to search for
---@return {path:string, timestamp:table|nil, display:string}[]
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
          local ts_str = filename:match("^journal_(.+)$")
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

--- Collect tag usage counts across all journal entries.
--- Note: this scans the journal folder only. For wiki-wide tags use
--- citations.get_all_tags() instead.
---@return table<string, integer> Map of tag string to occurrence count
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
