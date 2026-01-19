-- lua/pkm/yaml.lua
local M = {}

--- Helper: Safe String Quoting for YAML
local function quote_string(str)
  if not str then return "" end
  -- Escape double quotes and wrap in double quotes
  return string.format('"%s"', str:gsub('"', '\\"'))
end

--- Helper: Parse Inline Table - { key: val, key2: "val" }
local function parse_inline_table(text)
  local clean = text:match("^%s*-%s*{(.+)}%s*$")
  if not clean then return nil end
  
  local result = {}
  -- Naive CSV split doesn't work for quoted strings with commas. 
  -- We use a pattern matching approach for specific expected keys.
  -- This is stricter but safer for your specific schema.
  local identifier = clean:match("identifier:%s*([^,}]+)")
  local title = clean:match('title:%s*"(.-[^\\])"') or clean:match("title:%s*([^,}]+)")
  local link = clean:match("link:%s*([^,}]+)")

  if identifier then result.identifier = vim.trim(identifier) end
  if title then result.title = title:gsub('\\"', '"') end -- Unescape
  if link then result.link = vim.trim(link) end
  
  return result
end

function M.parse_frontmatter(lines)
  local frontmatter = {}
  local content_start_index = 1
  
  if type(lines) == "string" then lines = vim.split(lines, "\n") end
  -- Check if file actually starts with YAML
  if not lines or #lines == 0 or lines[1] ~= "---" then 
      return nil, 1 
  end

  local current_key = nil      
  local current_section = nil  
  local current_sub = nil      
  local current_list_item = nil 

  for i = 2, #lines do
    local line = lines[i]
    if line == "---" or line == "..." then
      content_start_index = i + 1
      break
    end
    
    -- 1. Top Level Keys
    local key, val = line:match("^(%w+):%s*(.*)")
    if key then
      current_key = key
      if val == "" then
         -- Section Start (cites:, cited_by:, tags:)
         if key == "tags" then
             frontmatter.tags = {}
         else
             frontmatter[key] = {} 
         end
         current_section = key
         current_sub = nil
      else
         -- Scalar Value
         -- Remove surrounding quotes only
         val = val:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
         frontmatter[key] = val
         current_section = nil
      end

    -- 2. Subsections (notes:, journal:)
    elseif current_section and line:match("^%s+%w+:$") then
      local sub = line:match("^%s+(%w+):")
      current_sub = sub
      if not frontmatter[current_section] then frontmatter[current_section] = {} end
      frontmatter[current_section][sub] = {}

    -- 3. Tag List Items
    elseif current_key == "tags" and line:match("^%s+-%s+") then
      local tag_val = line:match("^%s+-%s+(.*)")
      if tag_val then
         tag_val = tag_val:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
         table.insert(frontmatter.tags, tag_val)
      end

    -- 4. Inline Citation Items ( - { ... })
    elseif current_section and current_sub and line:match("^%s+-%s+{") then
      local item = parse_inline_table(line)
      if item then
        table.insert(frontmatter[current_section][current_sub], item)
      end
      
    -- 5. Block Citation Start ( - )
    elseif current_section and current_sub and line:match("^%s+-$") then
       current_list_item = {}
       table.insert(frontmatter[current_section][current_sub], current_list_item)
       
    -- 6. Block Citation Properties ( title: ... )
    elseif current_section and current_sub and current_list_item and line:match("^%s+%w+:") then
       local k, v = line:match("^%s+(%w+):%s*(.*)")
       if k and v then
          v = v:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
          current_list_item[k] = v
       end
    end
  end

  return frontmatter, content_start_index
end

function M.generate_yaml(fm)
  local lines = {}
  
  -- 1. Priority Metadata
  local priority_keys = {"title", "author", "status", "created_on", "last_updated_on", "type"}
  for _, k in ipairs(priority_keys) do
    if fm[k] then 
        table.insert(lines, string.format("%s: %s", k, quote_string(fm[k]))) 
    end
  end

  -- 2. Tags
  if fm.tags and #fm.tags > 0 then
    table.insert(lines, "tags:")
    for _, tag in ipairs(fm.tags) do
      table.insert(lines, string.format("  - %s", quote_string(tag)))
    end
  end

  -- 3. Citations (Separated Blocks)
  for _, section in ipairs({"cites", "cited_by"}) do
    if fm[section] then
      local has_content = false
      -- Check content existence
      for _, list in pairs(fm[section]) do
        if #list > 0 then has_content = true break end
      end
      
      if has_content then
        table.insert(lines, section .. ":")
        -- Explicit ordering: bib, notes, journal
        for _, sub in ipairs({"bib", "notes", "journal"}) do
          if fm[section][sub] and #fm[section][sub] > 0 then
            table.insert(lines, "  " .. sub .. ":")
            for _, item in ipairs(fm[section][sub]) do
              -- Output as Valid Flow-Style YAML
              local parts = {}
              if item.identifier then table.insert(parts, "identifier: " .. item.identifier) end
              if item.title then table.insert(parts, "title: " .. quote_string(item.title)) end
              if item.link then table.insert(parts, "link: " .. quote_string(item.link)) end
              
              table.insert(lines, string.format("    - { %s }", table.concat(parts, ", ")))
            end
          else
            -- Explicit empty array for clarity
            table.insert(lines, string.format("  %s: []", sub))
          end
        end
      end
    end
  end
  
  return lines
end

function M.save_frontmatter(fm, content_start, filepath)
  local all_lines = vim.fn.readfile(filepath)
  local content = {}
  
  if content_start <= #all_lines then
    for i = content_start, #all_lines do
      table.insert(content, all_lines[i])
    end
  end

  local new_lines = {"---"}
  local yaml_lines = M.generate_yaml(fm)
  for _, l in ipairs(yaml_lines) do table.insert(new_lines, l) end
  table.insert(new_lines, "---")
  
  if #content > 0 and content[1] ~= "" then table.insert(new_lines, "") end
  for _, l in ipairs(content) do table.insert(new_lines, l) end

  vim.fn.writefile(new_lines, filepath)
end

return M
