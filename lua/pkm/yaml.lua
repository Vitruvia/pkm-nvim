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
    vim.notify("PKM Warning: malformed frontmatter delimiter in "
        .. vim.fn.expand("%:t"), vim.log.levels.WARN)
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
--- Uses strict indentation tracking to handle object arrays correctly.
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
