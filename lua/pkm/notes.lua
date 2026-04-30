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
  
  vim.notify("Created: " .. filename, vim.log.levels.INFO)
  return filepath
end

--- Promote current scratchpad to consolidated or journal
--- Uses Telescope if available, vim.ui.select as fallback
function M.promote_note()
  local current_path = vim.fn.expand("%:p")

  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end

  if not current_path:find(config.folders.scratchpad, 1, true) then
    vim.notify("PKMPromote: only works on scratchpad notes. Use :PKMConvertNote for other types.", vim.log.levels.WARN)
    return
  end

  local targets = {
    { label = "Consolidated Note",  value = "note" },
    { label = "Journal Entry",      value = "journal" },
    { label = "Cancel",             value = "cancel" },
  }

  -- Check Telescope at call time, not at load time
  local has_telescope = package.loaded['telescope'] ~= nil
  if has_telescope then
    local ok, pickers      = pcall(require, "telescope.pickers")
    local _,  finders      = pcall(require, "telescope.finders")
    local _,  conf         = pcall(require, "telescope.config")
    local _,  actions      = pcall(require, "telescope.actions")
    local _,  action_state = pcall(require, "telescope.actions.state")

    if ok then
      pickers.new({}, {
        prompt_title = "Promote scratchpad to:",
        finder = finders.new_table {
          results = targets,
          entry_maker = function(entry)
            return { value = entry, display = entry.label, ordinal = entry.label }
          end,
        },
        sorter = conf.values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            if sel and sel.value.value ~= "cancel" then
              M.do_convert(current_path, "scratchpad", sel.value.value)
            end
          end)
          return true
        end,
      }):find()
      return
    end
  end

  -- Fallback
  vim.ui.select(targets, {
    prompt = "Promote scratchpad to:",
    format_item = function(item) return item.label end,
  }, function(sel)
    if sel and sel.value ~= "cancel" then
      M.do_convert(current_path, "scratchpad", sel.value)
    end
  end)
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

function M.create_scratchpad()
  vim.fn.inputsave()
  local title = vim.fn.input("Scratchpad title (optional, Enter to skip): ")
  vim.fn.inputrestore()

  local ts = timestamp.now()
  local filename = timestamp.create_filename("scratch", ts, ".md")

  local scratchpad_path = join_path(config.root_path, config.folders.scratchpad)
  ensure_dir(scratchpad_path)

  local filepath = join_path(scratchpad_path, filename)

  -- Only pass title to frontmatter if the user provided one
  local fm_data = title ~= "" and { title = title } or {}

  local frontmatter_lines = yaml.create_frontmatter("scratchpad", fm_data)
  table.insert(frontmatter_lines, "")

  vim.fn.writefile(frontmatter_lines, filepath)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  vim.cmd("normal! G")
  vim.notify("Created scratchpad: " .. filename, vim.log.levels.INFO)
  return filepath
end

--- Convert note to the current folder's type: normalize current note to the
--- format required by its PKM folder. Adds missing frontmatter fields,
--- preserves existing ones. For consolidated notes without a valid PKM
--- filename, prompts for type/title and renames the file.
function M.convert_note()
  local current_path = vim.fn.expand("%:p")

  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end

  -- Detect which PKM folder the file lives in
  local folder_type
  if current_path:find(config.folders.scratchpad, 1, true) then
    folder_type = "scratchpad"
  elseif current_path:find(config.folders.journal, 1, true) then
    folder_type = "journal"
  elseif current_path:find(config.folders.consolidated, 1, true) then
    folder_type = "consolidated"
  else
    vim.notify("PKMConvertNote: file is not inside a PKM folder", vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local existing_fm, content_start = yaml.parse_frontmatter(lines)
  existing_fm = existing_fm or {}

  -- Collect body lines (everything after frontmatter)
  local content = {}
  for i = content_start, #lines do
    table.insert(content, lines[i])
  end

  -- Write merged frontmatter back to disk and reload the buffer.
  -- create_frontmatter(key, existing_fm) keeps all existing values and
  -- fills in any missing fields from the template.
  local function apply_in_place(fm_key)
    local new_fm_lines = yaml.create_frontmatter(fm_key, existing_fm)
    local new_content = vim.list_extend(new_fm_lines, content)
    vim.fn.writefile(new_content, current_path)
    vim.cmd("edit!")
    vim.notify("Converted to " .. folder_type .. " format", vim.log.levels.INFO)
  end

  if folder_type == "scratchpad" then
    apply_in_place("scratchpad")

  elseif folder_type == "journal" then
    apply_in_place("journal")

  elseif folder_type == "consolidated" then
    local basename    = vim.fn.fnamemodify(current_path, ":t:r")
    local number, note_type_part = basename:match("^(%d+)_([a-z]+)_")

    if number and note_type_part then
      -- File is already properly named: sync title from filename if absent
      if not existing_fm.title or existing_fm.title == "" then
        local name_part = basename:match("^%d+_[a-z]+_(.+)$")
        existing_fm.title = name_part and name_part:gsub("_", " ") or "Unnamed Note"
      end
      local fm_key = (note_type_part == "bib") and "bibliography" or "consolidated"
      apply_in_place(fm_key)

    else
      -- File does not follow PKM naming: prompt for type and title, then rename
      local note_types = {
        { label = "Regular Note",         value = "note" },
        { label = "Aggregate/Collection", value = "agg"  },
        { label = "Bibliography Entry",   value = "bib"  },
      }

      vim.ui.select(note_types, {
        prompt = "Note type:",
        format_item = function(item) return item.label end,
      }, function(type_sel)
        if not type_sel then
          vim.notify("Conversion cancelled", vim.log.levels.INFO)
          return
        end

        local default_title = (existing_fm.title and existing_fm.title ~= "")
          and existing_fm.title
          or basename:gsub("_", " ")

        vim.fn.inputsave()
        local title = vim.fn.input("Note title: ", default_title)
        vim.fn.inputrestore()
        if title == "" then title = "Unnamed Note" end
        existing_fm.title = title

        local note_number = get_next_note_number()
        local safe_title  = sanitize_title(title)
        local new_filename = string.format(
          "%04d_%s_%s.md", note_number, type_sel.value, safe_title
        )
        local dir      = vim.fn.fnamemodify(current_path, ":h")
        local new_path = join_path(dir, new_filename)

        if vim.fn.filereadable(new_path) == 1 then
          vim.notify("Cannot convert: target already exists: " .. new_filename, vim.log.levels.ERROR)
          return
        end

        local fm_key = (type_sel.value == "bib") and "bibliography" or "consolidated"
        local new_fm_lines = yaml.create_frontmatter(fm_key, existing_fm)
        local new_content  = vim.list_extend(new_fm_lines, content)
        vim.fn.writefile(new_content, new_path)

        vim.fn.inputsave()
        local del = vim.fn.input("Delete original file? (y/N): ")
        vim.fn.inputrestore()
        if del:lower() == "y" then
          vim.fn.delete(current_path)
        end

        vim.cmd("edit " .. vim.fn.fnameescape(new_path))
        vim.notify("Converted to: " .. new_filename, vim.log.levels.INFO)
      end)
    end
  end
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

--- Shared finalisation: optionally delete original, open new file
--- @param original_path string
--- @param new_path string
local function _finish_convert(original_path, new_path)
  vim.fn.inputsave()
  local delete_original = vim.fn.input("Delete original? (y/N): ")
  vim.fn.inputrestore()

  if delete_original:lower() == "y" then
    vim.fn.delete(original_path)
    vim.notify("Original deleted: " .. vim.fn.fnamemodify(original_path, ":t"), vim.log.levels.INFO)
  end

  vim.cmd("edit " .. vim.fn.fnameescape(new_path))
  vim.notify("Promoted to: " .. vim.fn.fnamemodify(new_path, ":t"), vim.log.levels.INFO)
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
    -- Prompt for consolidated note subtype
    local note_types = {
      { label = "Regular Note",         value = "note" },
      { label = "Aggregate/Collection", value = "agg"  },
      { label = "Bibliography Entry",   value = "bib"  },
    }
  
    vim.ui.select(note_types, {
      prompt = "Consolidated note type:",
      format_item = function(item) return item.label end,
    }, function(type_sel)
      if not type_sel then
        vim.notify("Conversion cancelled", vim.log.levels.INFO)
        return
      end
  
      vim.fn.inputsave()
      local title = vim.fn.input("Note title (leave empty for unnamed): ")
      vim.fn.inputrestore()
  
      local note_number = get_next_note_number()
      local safe_title  = sanitize_title(title)
      local note_filename = string.format(
        "%04d_%s_%s.md", note_number, type_sel.value,
        safe_title ~= "" and safe_title or "unnamed"
      )
  
      local consolidated_path = join_path(config.root_path, config.folders.consolidated)
      ensure_dir(consolidated_path)
      new_path = join_path(consolidated_path, note_filename)
  
      local fm_data = {
        title  = title ~= "" and title or "Unnamed Note",
      }
  
      if existing_fm then
        if existing_fm.tags   then fm_data.tags   = existing_fm.tags   end
        if existing_fm.author then fm_data.author = existing_fm.author end
      end
  
      local new_frontmatter = yaml.create_frontmatter("consolidated", fm_data)
      local new_content     = vim.list_extend(new_frontmatter, content)
      vim.fn.writefile(new_content, new_path)
  
      -- Continue to the "ask to delete original / open new file" block below
      _finish_convert(current_path, new_path)
    end)
    return  -- async from here; _finish_convert handles the rest
  end
  
  -- Ask whether to delete original
  _finish_convert(current_path, new_path)
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

function M.import_note()
  local current_path = vim.fn.expand("%:p")
  local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  
  -- Check if already in system
  if current_path ~= "" and current_path:find(config.root_path, 1, true) then
    vim.notify("This file is already in your PKM system.", vim.log.levels.WARN)
    return
  end

  -- Parse any existing frontmatter
  local existing_fm, content_start = yaml.parse_frontmatter(current_lines)
  local title_guess = "Imported Note"
  
  if existing_fm and existing_fm.title then
    title_guess = existing_fm.title
  elseif current_path ~= "" then
    title_guess = vim.fn.fnamemodify(current_path, ":t:r")
  elseif content_start and current_lines[content_start] then
    -- Try to guess title from first line if it looks like a header
    local first_line = current_lines[content_start]
    if first_line:match("^#+ ") then
        title_guess = first_line:gsub("^#+ ", "")
    end
  end

  -- Prompt for Type
  vim.ui.select({"note", "bib", "agg"}, { prompt = "Select Import Type:" }, function(selected_type)
    if not selected_type then return end
    
    -- Prompt for Title
    vim.ui.input({ prompt = "Title: ", default = title_guess }, function(input_title) 
      if input_title == nil then return end -- Cancelled
      local title = input_title
      if title == "" then title = "Unnamed" end

      -- Prepare Metadata
      local fm_data = existing_fm or {}
      fm_data.title = title
      if not fm_data.created_on then fm_data.created_on = timestamp.to_iso8601() end
      
      -- If bib, ensure source fields exist (prompt optional, or just blank)
      if selected_type == "bib" then
         if not fm_data.source_author then fm_data.source_author = "" end
         if not fm_data.source_type then fm_data.source_type = "book" end
      end

      -- Generate Target Path
      local note_number = get_next_note_number()
      local safe_title = sanitize_title(title)
      local filename = string.format("%04d_%s_%s.md", note_number, selected_type, safe_title)
      local target_path = join_path(config.root_path, config.folders.consolidated, filename)
      ensure_dir(vim.fn.fnamemodify(target_path, ":h"))

      -- Prevent overwrite
      if vim.fn.filereadable(target_path) == 1 then
         vim.notify("Cannot import: ID collision or file exists (" .. filename .. ")", vim.log.levels.ERROR)
         return
      end

      -- Generate New Frontmatter
      local template_type = (selected_type == "bib") and "bibliography" or "consolidated"
      local new_fm_lines = yaml.create_frontmatter(template_type, fm_data)
      
      -- Construct Final Content
      local final_content = {}
      for _, l in ipairs(new_fm_lines) do table.insert(final_content, l) end
      
      -- Append original body (skip original FM if it existed)
      local start_line = existing_fm and content_start or 1
      for i = start_line, #current_lines do
        table.insert(final_content, current_lines[i])
      end

      -- Write File
      vim.fn.writefile(final_content, target_path)
      
      -- Handle Old Buffer/File
      local delete_old = false
      if current_path ~= "" and vim.fn.filereadable(current_path) == 1 then
        vim.ui.select({"Delete original", "Keep original"}, { prompt = "Import successful. Original file:" }, function(choice)
            if choice == "Delete original" then
                vim.fn.delete(current_path)
            end
            -- Switch buffer to new file
            vim.cmd("edit " .. vim.fn.fnameescape(target_path))
        end)
      else
        -- Unnamed buffer, just switch
        vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      end
      
      vim.notify("Imported: " .. filename, vim.log.levels.INFO)
    end)
  end)
end

return M
