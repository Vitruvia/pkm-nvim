-- lua/pkm/core.lua
local M = {}
local config = {}
local path_sep = package.config:sub(1, 1)

function M.setup(user_config)
  config = user_config
end

local function join_path(...) 
  return table.concat({...}, path_sep) 
end

function M.new_note(title)
  -- Prompt for title if not provided
  if not title or title == "" then
    vim.ui.input({ prompt = "Note Title: " }, function(input)
      if input then M.create_note_file(input, "note") end
    end)
  else
    M.create_note_file(title, "note")
  end
end

function M.new_journal()
  local date = os.date("%Y-%m-%d")
  -- Check if today's journal exists
  local filename = "journal_" .. date .. ".md"
  local filepath = join_path(config.root_path, config.folders.journal, filename)
  
  if vim.fn.filereadable(filepath) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  else
    M.create_note_file(date, "journal")
  end
end

function M.create_note_file(name, type)
  local filename, folder, id
  
  if type == "journal" then
    filename = "journal_" .. name .. ".md"
    folder = config.folders.journal
    id = "journal-" .. name
  else
    -- Find next ID for Consolidated notes
    local search_path = join_path(config.root_path, config.folders.consolidated)
    local files = vim.fn.glob(search_path .. "/*.md", false, true)
    local max_id = 0
    for _, f in ipairs(files) do
      local num = f:match("^(%d+)_")
      if num then max_id = math.max(max_id, tonumber(num)) end
    end
    local next_id = string.format("%04d", max_id + 1)
    
    -- Sanitize title
    local safe_name = name:lower():gsub(" ", "-"):gsub("[^a-z0-9%-]", "")
    filename = next_id .. "_note_" .. safe_name .. ".md"
    folder = config.folders.consolidated
    id = "note-" .. next_id
  end
  
  local filepath = join_path(config.root_path, folder, filename)
  
  -- Create directory if needed
  local full_dir = join_path(config.root_path, folder)
  if vim.fn.isdirectory(full_dir) == 0 then
    vim.fn.mkdir(full_dir, "p")
  end

  -- Initial Content
  local lines = {
    "---",
    "title: " .. (type == "journal" and name or name),
    "date: " .. os.date("%Y-%m-%d"),
    "type: " .. type,
    "tags:",
    "  - ",
    "cites:",
    "  notes: []",
    "  bib: []",
    "  journal: []",
    "cited_by:",
    "  notes: []",
    "  bib: []",
    "  journal: []",
    "---",
    "",
    "# " .. name,
    ""
  }
  
  vim.fn.writefile(lines, filepath)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
end

return M
