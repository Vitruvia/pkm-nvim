-- =============================================================================
-- pkm.yaml — YAML frontmatter parsing and generation
-- =============================================================================
-- Dependencies : pkm.timestamp
-- Consumed by  : virtually all modules (citations, notes, journal, export...)
--
-- WARNING: This module contains carefully fixed parser logic. Do not modify
-- parse_yaml or generate_yaml without strong justification and thorough testing.
-- Silent regressions here corrupt note files.
--
-- Public API:
--   setup(user_config)                    → Initialize with resolved PKM config
--   parse_frontmatter(lines)              → (frontmatter, content_start) from line array
--   parse_yaml(lines)                     → table from raw YAML lines
--   parse_value(value)                    → typed Lua value from YAML string
--   generate_yaml(data, indent?)          → string[] YAML lines from table
--   format_value(value)                   → YAML-safe string from Lua value
--   create_frontmatter(note_type, data?)  → string[] full frontmatter block with delimiters
--   save_frontmatter(fm, content_start, filepath?) → write fm to buffer or file
--   update_last_modified()                → update last_updated_on in current
--                                           buffer
--   update_frontmatter()                  → interactive field editor
--   validate_frontmatter()                → check required fields against template
--   set_field(key, value)                 → set one frontmatter field in current buffer
--   get_field(key)                        → read one frontmatter field from current buffer
-- =============================================================================
local M = {}

local config = {}
local timestamp_module = nil

-- =============================================================================
-- SECTION: Setup
-- =============================================================================
---@param user_config table Resolved PKM config from pkm.config.resolve()
function M.setup(user_config)
  config = user_config
  timestamp_module = require('pkm.timestamp')
end

-- =============================================================================
-- SECTION: Parsing
-- =============================================================================
--- Parse YAML frontmatter block from an array of file lines. Returns nil
--- frontmatter if no valid --- delimiters are found. NOTE: The first line must
--- be exactly "---" with no trailing whitespace.
---@param lines string[]
---@return table|nil frontmatter Parsed frontmatter table, or nil if
---        absent/malformed 
---@return integer content_start 1-based index of first line after the closing 
---        "---"
function M.parse_frontmatter(lines)
  if not lines or #lines == 0 then
    return nil, 1
  end

  local first_line = lines[1]:gsub("\r$", "")
  
  if first_line ~= "---" then
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

--- Parse raw YAML lines into a Lua table. Handles nested maps, arrays, object
--- arrays, and explicit empty arrays ([]). Uses an indent stack to resolve
--- nesting without regex.
---@param lines string[]
---@return table
function M.parse_yaml(lines)
  local result = {}
  local indent_stack = {{key = nil, indent = -1, table = result}}
  
  for _, line in ipairs(lines) do
    -- Skip empty lines and comments
    if line:match("^%s*$") or line:match("^%s*#") then goto continue end
    
    local indent = #line:match("^%s*")
    local content = line:gsub("^%s+", "")
    
    -- Handle array items
    if content:match("^%-") then
      local value = content:match("^%-%s*(.*)")
      
      -- Find the correct array parent based on indentation
      while #indent_stack > 1 and indent <= indent_stack[#indent_stack].indent do
        table.remove(indent_stack)
      end
      
      local target_array = indent_stack[#indent_stack].table
      
      if type(target_array) ~= "table" then
        vim.notify("Invalid array context", vim.log.levels.WARN)
        goto continue
      end
      
      -- Handle multi-line array items (object items)
      if value == "" or value:match("^%s*$") then
        local item_table = {}
        table.insert(target_array, item_table)
        table.insert(indent_stack, {
          key = nil,
          indent = indent,
          table = item_table,
          is_array_item = true
        })
      else
        table.insert(target_array, M.parse_value(value))
      end
      goto continue
    end
    
    -- Handle key-value pairs
    local key, value = content:match("^([%w_%-]+):%s*(.*)")
    if key then
      -- Find correct target table based on indentation
      while #indent_stack > 1 and indent <= indent_stack[#indent_stack].indent do
        table.remove(indent_stack)
      end
      
      local target_table = indent_stack[#indent_stack].table
      
      -- Handle explicit empty array notation []
      if value == "[]" then
        target_table[key] = {}
      elseif value == "" or value:match("^%s*$") then
        local nested_table = {}
        target_table[key] = nested_table
        table.insert(indent_stack, {
          key = key,
          indent = indent,
          table = nested_table
        })
      else
        target_table[key] = M.parse_value(value)
      end
    end
    
    ::continue::
  end
  
  return result
end

--- Convert a raw YAML value string to a typed Lua value.
--- Handles: null/~, true/false, numbers, quoted strings, bare strings.
---@param value string
---@return any
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

-- =============================================================================
-- SECTION: Generation
-- =============================================================================
--- Serialize a Lua table to YAML lines with a fixed key ordering.
--- Empty tables emit "key: []". Nested maps and object arrays are indented.
--- Key order: title, author, source_author, tags, created_on, last_updated_on,
---            cites, cited_by, citation, source_type, source_location, then rest.
---@param data table
---@param indent integer? Indentation level (default 0, each level = 2 spaces)
---@return string[]
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

--- Format a single Lua value as a YAML-safe string.
--- Strings containing non-word characters are double-quoted.
---@param value any
---@return string
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

-- =============================================================================
-- SECTION: Frontmatter construction
-- =============================================================================
--- Build a complete frontmatter block for a new note.
--- Deep-copies the template for note_type, merges custom_data over it,
--- replaces "ISO8601" sentinel values with current timestamps,
--- then wraps the result in "---" delimiters.
---@param note_type string Key into config.frontmatter_templates (e.g. "note",
---       "bib", "journal")
---@param custom_data table|nil Fields to merge over the template (title,
---       author, etc.)
---@return string[] Lines including opening "---", YAML, closing "---", and
---        blank line
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

--- Update last_updated_on in the current buffer if it differs from now.
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

-- =============================================================================
-- SECTION: Saving
-- =============================================================================
--- Write updated frontmatter back to the current buffer (Case A) or a file
--- (Case B).
--- Case A (filepath nil): replaces lines 0..content_start-1 in the current buffer.
--- Case B (filepath set): reads the file, rebuilds content with new
---                        frontmatter, writes to disk.
--- Preserves or adds a blank line between frontmatter and body.
---@param frontmatter table Updated frontmatter table
---@param content_start integer|nil 1-based line index of first body line (Case
---       A only)
---@param filepath string|nil Absolute path for disk write; nil to write to
---       current buffer
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

-- =============================================================================
-- SECTION: Validation and field access
-- =============================================================================
--- Validate that the current buffer's frontmatter contains all fields
--- required by its note type template. Reports missing fields.
---@return boolean valid
function M.validate_frontmatter()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, _ = M.parse_frontmatter(lines)
  
  if not frontmatter then
    vim.notify("No frontmatter found", vim.log.levels.ERROR)
    return false
  end
  
  local filepath = vim.fn.expand("%:p")
  local template_key

  if filepath:find(config.folders.journal, 1, true) then
    template_key = "journal"
  elseif filepath:find(config.folders.scratchpad, 1, true) then
    template_key = "scratchpad"
  elseif filepath:find(config.folders.consolidated, 1, true) then
    local note_type_part = vim.fn.fnamemodify(filepath, ":t:r"):match("^%d+_([a-z]+)_")
    if note_type_part == "bib" then template_key = "bibliography"
    elseif note_type_part == "agg" then template_key = "agg"
    else template_key = "note" end
  else
    vim.notify("Unknown note type, cannot validate", vim.log.levels.WARN)
    return false
  end
  
  local template = config.frontmatter_templates[template_key]
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

--- Set a single frontmatter field in the current buffer and save.
---@param key string
---@param value any
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

--- Read a single frontmatter field from the current buffer.
---@param key string
---@return any|nil
function M.get_field(key)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local frontmatter, _ = M.parse_frontmatter(lines)
  
  if not frontmatter then
    return nil
  end
  
  return frontmatter[key]
end

return M
