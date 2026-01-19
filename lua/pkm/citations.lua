-- lua/pkm/citations.lua
local M = {}
local config = {}
local yaml = nil
local path_sep = package.config:sub(1, 1)

-- Cache
local items_cache = nil
local tag_cache = nil -- New: Cache for tags
local cache_dirty = true

function M.setup(user_config)
  config = user_config
  yaml = require('pkm.yaml')
  
  -- Auto-invalidate cache on save
  local group = vim.api.nvim_create_augroup("PKMCache", { clear = true })
  vim.api.nvim_create_autocmd({"BufWritePost", "FileWritePost"}, {
    pattern = "*.md",
    group = group,
    callback = function() M.invalidate_cache() end
  })
end

function M.invalidate_cache()
  items_cache = nil
  tag_cache = nil
  cache_dirty = true
end

local function join_path(...) 
  return table.concat({...}, path_sep) 
end

function M.parse_citation_tag(text) 
  return text:match("(%w+)%[([%w%-_]+)%]") 
end

function M.get_note_type_and_id(filepath)
  local filename = vim.fn.fnamemodify(filepath, ":t:r")
  local number, type_str = filename:match("^(%d+)_([a-z]+)_")
  if number and type_str then
    local final_type = (type_str == "bib") and "bib" or "note"
    return final_type, final_type .. "-" .. number
  end
  local prefix = filename:match("^([a-z]+)_")
  if prefix == "journal" then return "journal", filename end
  return "note", filename 
end

-- Read File to get Title and Tags
function M.read_note_metadata(filepath)
  local content = vim.fn.readfile(filepath)
  local fm, _ = yaml.parse_frontmatter(content)
  
  local title = vim.fn.fnamemodify(filepath, ":t:r")
  local tags = {}

  if fm then
    if fm.title and fm.title ~= "" then title = fm.title end
    if fm.tags then tags = fm.tags end
  end
  
  return title, tags
end

-- Build Cache
function M.get_data()
  if items_cache and tag_cache and not cache_dirty then 
    return items_cache, tag_cache 
  end

  local items = {}
  local all_tags = {}
  
  local search_paths = {
    config.folders.consolidated, 
    config.folders.journal, 
    config.folders.scratchpad
  }
  
  for _, folder in ipairs(search_paths) do
    local search_path = join_path(config.root_path, folder)
    local files = vim.fn.glob(search_path .. "/*.md", false, true)
    
    for _, file in ipairs(files) do
      local type, id = M.get_note_type_and_id(file)
      if id then
        local title, note_tags = M.read_note_metadata(file)
        
        items[id] = {
          path = file,
          basename = vim.fn.fnamemodify(file, ":t:r"),
          type = type,
          title = title,
          tags = note_tags
        }
        
        -- Aggregate unique tags
        for _, t in ipairs(note_tags) do
          all_tags[t] = true
        end
      end
    end
  end
  
  items_cache = items
  tag_cache = vim.tbl_keys(all_tags)
  table.sort(tag_cache)
  
  cache_dirty = false
  return items, tag_cache
end

-- API for Telescope
function M.get_all_tags()
  local _, tags = M.get_data()
  return tags
end

function M.get_citable_items_list()
  local map, _ = M.get_data()
  local list = {}
  for id, data in pairs(map) do
    local short_id = id:match("note%-(%d+)") or id:match("bib%-(%d+)") or id
    table.insert(list, {
      type = data.type,
      identifier = id,
      short_id = short_id,
      display = string.format("[%s] %s (%s)", data.type, data.title, short_id),
      path = data.path,
      basename = data.basename
    })
  end
  table.sort(list, function(a, b) return a.display < b.display end)
  return list
end

-- Standard update logic (Kept same as before)
local function ensure_grouped_structure(fm, key)
    if not fm[key] then fm[key] = {} end
    if not fm[key].notes then fm[key].notes = {} end
    if not fm[key].bib then fm[key].bib = {} end
    if not fm[key].journal then fm[key].journal = {} end
end

function M.update_references()
  local current_path = vim.fn.expand("%:p")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local fm, content_start = yaml.parse_frontmatter(lines)
  if not fm then return end

  local new_citations = {}
  local all_items, _ = M.get_data()
  
  for i = content_start, #lines do
    for match in lines[i]:gmatch("%w+%[[%w%-_]+%]") do
       local type, id_part = M.parse_citation_tag(match)
       for full_id, item in pairs(all_items) do
          if (item.type == type) and (full_id:find(id_part, 1, true)) then
             new_citations[full_id] = item
             break
          end
       end
    end
  end

  ensure_grouped_structure(fm, 'cites')
  fm.cites.notes = {}
  fm.cites.bib = {}
  fm.cites.journal = {}
  
  for id, item in pairs(new_citations) do
     local bucket = "notes"
     if item.type == "bib" then bucket = "bib" end
     if item.type == "journal" then bucket = "journal" end
     
     table.insert(fm.cites[bucket], {
        identifier = id,
        title = item.title,
        link = "[[" .. item.basename .. "]]"
     })
  end
  
  yaml.save_frontmatter(fm, content_start, current_path)
  
  -- Backlinks (Separated Buckets)
  local current_type, current_id = M.get_note_type_and_id(current_path)
  if current_id then
      for id, item in pairs(new_citations) do
          M.add_backlink(item.path, current_path, current_id)
      end
  end
end

function M.add_backlink(target_path, source_path, source_id)
    if target_path == source_path then return end
    local content = vim.fn.readfile(target_path)
    local fm, content_start = yaml.parse_frontmatter(content)
    if not fm then return end
    
    ensure_grouped_structure(fm, 'cited_by')
    local source_type, _ = M.get_note_type_and_id(source_path)
    local bucket = (source_type == "bib") and "bib" or ((source_type == "journal") and "journal" or "notes")
    
    local exists = false
    if fm.cited_by[bucket] then
        for _, entry in ipairs(fm.cited_by[bucket]) do
            if entry.identifier == source_id then exists = true break end
        end
    end
    
    if not exists then
        local title, _ = M.read_note_metadata(source_path)
        table.insert(fm.cited_by[bucket], {
            identifier = source_id,
            title = title,
            link = "[[" .. vim.fn.fnamemodify(source_path, ":t:r") .. "]]"
        })
        yaml.save_frontmatter(fm, content_start, target_path)
    end
end

return M
