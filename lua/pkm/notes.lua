-- =============================================================================
-- pkm.notes — Note creation, conversion, promotion, and navigation
-- =============================================================================
-- Dependencies : pkm.yaml, pkm.utils, pkm.timestamp, pkm.citations (lazy)
-- Consumed by  : pkm.commands, pkm.keymaps
--
-- Public API:
--   setup(user_config)                        → Initialize with resolved PKM config
--   create_new_note(note_type?)               → Create consolidated note (prompts if nil)
--   create_scratchpad()                       → Create timestamped scratchpad note
--   promote_note()                            → Promote scratchpad to consolidated or journal
--   do_convert(current_path, current_type, target) → Perform note type conversion
--   convert_note()                            → Normalize current note to its folder's format
--   change_note_type()                        → Change type of consolidated note and rename file
--   transpose_note()                          → Move note to different folder and convert
--   rename_note()                             → Prompt for new name and rename current note
--   link_to_note()                            → Insert [[wiki-link]] at cursor
--   follow_link()                             → Open note linked under cursor
--   show_backlinks()                          → Show all notes linking to current note
--   import_note()                             → Import external file into PKM structure
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
-- SECTION: File naming helpers
-- =============================================================================
--- Get next available note number
local function get_next_note_number()
  local consolidated_path = utils.join(config.root_path, config.folders.consolidated)
  local files = vim.fn.glob(consolidated_path .. utils.sep .. "*.md", false, true)
  
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

-- =============================================================================
-- SECTION: Note creation
-- =============================================================================
--- Create a new consolidated note in the configured consolidated folder.
--- Prompts for type if not provided, then for title. Handles bib-specific
--- fields (source_author, source_type) when type is "bib".
---@param note_type string|nil "note", "agg", or "bib" — prompts if nil
---@return string|nil filepath Absolute path of created note, or nil on cancel
function M.create_new_note(note_type)
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
  
  local consolidated_path = utils.join(config.root_path, config.folders.consolidated)
  utils.ensure_dir(consolidated_path)
  
  local filepath = utils.join(consolidated_path, filename)
  
  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("File already exists: " .. filename, vim.log.levels.ERROR)
    return nil
  end
  
  local fm_type = (note_type == "bib") and "bibliography"
             or (note_type == "agg") and "agg"
             or "note"
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
  
  -- Add a blank line for content
  table.insert(frontmatter_lines, "")
  
  vim.fn.writefile(frontmatter_lines, filepath)
  require('pkm.index').invalidate(filepath)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  
  vim.cmd("normal! G")
  
  vim.notify("Created: " .. filename, vim.log.levels.INFO)
  return filepath
end

--- Create a timestamped scratchpad note. Prompts for an optional title.
---@return string filepath Absolute path of created scratchpad
function M.create_scratchpad()
  vim.fn.inputsave()
  local title = vim.fn.input("Scratchpad title (optional, Enter to skip): ")
  vim.fn.inputrestore()

  local ts = timestamp.now()
  local filename = timestamp.create_filename("scratch", ts, ".md")

  local scratchpad_path = utils.join(config.root_path, config.folders.scratchpad)
  utils.ensure_dir(scratchpad_path)

  local filepath = utils.join(scratchpad_path, filename)

  -- Only pass title to frontmatter if the user provided one
  local fm_data = title ~= "" and { title = title } or {}

  local frontmatter_lines = yaml.create_frontmatter("scratchpad", fm_data)
  table.insert(frontmatter_lines, "")

  vim.fn.writefile(frontmatter_lines, filepath)
  require('pkm.index').invalidate(filepath)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  vim.cmd("normal! G")
  vim.notify("Created scratchpad: " .. filename, vim.log.levels.INFO)
  return filepath
end

-- =============================================================================
-- SECTION: Note promotion and conversion
-- =============================================================================
--- Promote the current scratchpad note to a consolidated note or journal entry.
--- Only works when the current buffer is inside the scratchpad folder.
--- Uses Telescope if available, falls back to vim.ui.select.
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

--- Move the current note to a different PKM folder and convert it to that
--- folder's format. Works from any folder, unlike promote_note which is
--- scratchpad-only. Presents all folders except the current one as targets,
--- then delegates to do_convert().
function M.transpose_note()
  local current_path = vim.fn.expand("%:p")

  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end

  local current_folder
  if current_path:find(config.folders.scratchpad, 1, true) then
    current_folder = "scratchpad"
  elseif current_path:find(config.folders.journal, 1, true) then
    current_folder = "journal"
  elseif current_path:find(config.folders.consolidated, 1, true) then
    current_folder = "consolidated"
  else
    vim.notify("PKMTranspose: file is not inside a PKM folder", vim.log.levels.ERROR)
    return
  end

  -- Offer all folders except the current one
  local all_targets = {
    { label = "Consolidated Note", value = "note"      },
    { label = "Journal Entry",     value = "journal"   },
    { label = "Scratchpad",        value = "scratchpad" },
  }

  local targets = {}
  for _, t in ipairs(all_targets) do
    local skip = (current_folder == "consolidated" and t.value == "note")
              or (current_folder == "journal"      and t.value == "journal")
              or (current_folder == "scratchpad"   and t.value == "scratchpad")
    if not skip then
      table.insert(targets, t)
    end
  end

  vim.ui.select(targets, {
    prompt = "Transpose note to:",
    format_item = function(item) return item.label end,
  }, function(sel)
    if not sel then
      vim.notify("Transpose cancelled", vim.log.levels.INFO)
      return
    end
    M.do_convert(current_path, current_folder, sel.value)
  end)
end

--- Ask whether to delete the original file, then open the new file.
--- Shared finalisation step used by do_convert after file creation.
---@param original_path string Absolute path of the source file
---@param new_path string Absolute path of the newly created file
local function _finish_convert(original_path, new_path)
  require('pkm.index').invalidate(new_path)   -- file just written; index it now

  vim.fn.inputsave()
  local delete_original = vim.fn.input("Delete original? (y/N): ")
  vim.fn.inputrestore()

  if delete_original:lower() == "y" then
    vim.fn.delete(original_path)
    require('pkm.index').invalidate(original_path)  -- remove stale entry
    vim.notify("Original deleted: " .. vim.fn.fnamemodify(original_path, ":t"), vim.log.levels.INFO)
  end

  vim.cmd("edit " .. vim.fn.fnameescape(new_path))
  vim.notify("Promoted to: " .. vim.fn.fnamemodify(new_path, ":t"), vim.log.levels.INFO)
end

--- Perform the actual file conversion from one note type to another.
--- Reads current buffer content, builds new frontmatter, writes to new path.
--- For target "note", prompts for subtype and title asynchronously.
---@param current_path string Absolute path of note being converted
---@param current_type string Source type: "scratchpad", "journal", or "note"
---@param target string Destination type: "note", "journal", or "scratchpad"
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
    local journal_path = utils.join(config.root_path, config.folders.journal)
    utils.ensure_dir(journal_path)
    new_path = utils.join(journal_path, journal_filename)
    
    local fm_data = {}

    if existing_fm and existing_fm.tags then
      fm_data.tags = existing_fm.tags
    end
    
    local new_frontmatter = yaml.create_frontmatter("journal", fm_data)
    local new_content = vim.list_extend(new_frontmatter, content)
    
    vim.fn.writefile(new_content, new_path)

    local old_basename = vim.fn.fnamemodify(current_path, ":t:r")
    local new_basename = vim.fn.fnamemodify(new_path, ":t:r")

    require('pkm.citations').update_references_on_rename(old_basename,
    new_basename, nil)
    
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
  
      local consolidated_path = utils.join(config.root_path, config.folders.consolidated)
      utils.ensure_dir(consolidated_path)
      new_path = utils.join(consolidated_path, note_filename)
  
      local fm_data = {
        title  = title ~= "" and title or "Unnamed Note",
      }
  
      if existing_fm then
        if existing_fm.tags   then fm_data.tags   = existing_fm.tags   end
        if existing_fm.author then fm_data.author = existing_fm.author end
      end
  
      local new_frontmatter = yaml.create_frontmatter("note", fm_data)
      local new_content     = vim.list_extend(new_frontmatter, content)
      vim.fn.writefile(new_content, new_path)

      local old_basename = vim.fn.fnamemodify(current_path, ":t:r")
      local new_basename = vim.fn.fnamemodify(new_path, ":t:r")
      require('pkm.citations').update_references_on_rename(old_basename, new_basename, fm_data.title)
  
      -- Continue to the "ask to delete original / open new file" block below
      _finish_convert(current_path, new_path)
    end)
    return  -- async from here; _finish_convert handles the rest
  elseif target == "scratchpad" then
    local ts = timestamp.now()
    local scratch_filename = timestamp.create_filename("scratch", ts, ".md")
    local scratch_path = utils.join(config.root_path, config.folders.scratchpad)
    utils.ensure_dir(scratch_path)
    new_path = utils.join(scratch_path, scratch_filename)
  
    local fm_data = {}
    if existing_fm and existing_fm.tags then
      fm_data.tags = existing_fm.tags
    end
  
    local new_frontmatter = yaml.create_frontmatter("scratchpad", fm_data)
    local new_content = vim.list_extend(new_frontmatter, content)
    vim.fn.writefile(new_content, new_path)
  
    local old_basename = vim.fn.fnamemodify(current_path, ":t:r")
    local new_basename = vim.fn.fnamemodify(new_path, ":t:r")
    require('pkm.citations').update_references_on_rename(old_basename, new_basename, nil)
  end


  
  -- Ask whether to delete original
  _finish_convert(current_path, new_path)
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
    require('pkm.index').invalidate(current_path)
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
    local fm_key = (note_type_part == "bib") and "bibliography"
            or (note_type_part == "agg") and "agg"
            or "note"
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
        local new_path = utils.join(dir, new_filename)

        if vim.fn.filereadable(new_path) == 1 then
          vim.notify("Cannot convert: target already exists: " .. new_filename, vim.log.levels.ERROR)
          return
        end

        local fm_key = (type_sel.value == "bib") and "bibliography"
            or (type_sel.value == "agg") and "agg"
            or "note"
        local new_fm_lines = yaml.create_frontmatter(fm_key, existing_fm)
        local new_content  = vim.list_extend(new_fm_lines, content)

        vim.fn.writefile(new_content, new_path)
        local old_basename = vim.fn.fnamemodify(current_path, ":t:r")
        local new_basename = vim.fn.fnamemodify(new_path, ":t:r")
        require('pkm.citations').update_references_on_rename(old_basename, new_basename, title)
        require('pkm.index').invalidate(new_path)

        vim.fn.inputsave()
        local del = vim.fn.input("Delete original file? (y/N): ")
        vim.fn.inputrestore()
        if del:lower() == "y" then
          vim.fn.delete(current_path)
          require('pkm.index').invalidate(current_path)
        end

        vim.cmd("edit " .. vim.fn.fnameescape(new_path))
        vim.notify("Converted to: " .. new_filename, vim.log.levels.INFO)
      end)
    end
  end
end

--- Change the type of an already-named consolidated note (note/agg/bib).
--- Renames the file to reflect the new type and propagates the change
--- through all citations via update_references_on_rename.
--- Only works on consolidated notes with a valid PKM filename.
function M.change_note_type()
  local current_path = vim.fn.expand("%:p")

  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end

  if not current_path:find(config.folders.consolidated, 1, true) then
    vim.notify("PKMChangeType: only works on consolidated notes.", vim.log.levels.ERROR)
    return
  end

  local basename = vim.fn.fnamemodify(current_path, ":t:r")
  local number, current_type = basename:match("^(%d+)_([a-z]+)_")

  if not number or not current_type then
    vim.notify("PKMChangeType: file does not have a valid PKM filename. Use :PKMConvertNote first.", vim.log.levels.WARN)
    return
  end

  local note_types = {
    { label = "Regular Note",         value = "note" },
    { label = "Aggregate/Collection", value = "agg"  },
    { label = "Bibliography Entry",   value = "bib"  },
  }

  -- Filter out current type
  local targets = {}
  for _, t in ipairs(note_types) do
    if t.value ~= current_type then
      table.insert(targets, t)
    end
  end

  vim.ui.select(targets, {
    prompt = string.format("Change type from '%s' to:", current_type),
    format_item = function(item) return item.label end,
  }, function(sel)
    if not sel then
      vim.notify("Type change cancelled.", vim.log.levels.INFO)
      return
    end

    local dir          = vim.fn.fnamemodify(current_path, ":h")
    local name_part    = basename:match("^%d+_[a-z]+_(.+)$")
    local new_filename = string.format("%04d_%s_%s.md", tonumber(number), sel.value, name_part)
    local new_path     = utils.join(dir, new_filename)

    if vim.fn.filereadable(new_path) == 1 then
      vim.notify("Cannot change type: target already exists: " .. new_filename, vim.log.levels.ERROR)
      return
    end

    -- Update frontmatter template
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local existing_fm, content_start = yaml.parse_frontmatter(lines)
    existing_fm = existing_fm or {}

    local content = {}
    for i = content_start, #lines do
      table.insert(content, lines[i])
    end

    local fm_key = (sel.value == "bib") and "bibliography"
               or (sel.value == "agg") and "agg"
               or "note"
    local new_fm_lines = yaml.create_frontmatter(fm_key, existing_fm)
    local new_content  = vim.list_extend(new_fm_lines, content)

    -- Rename file on disk
    if vim.fn.rename(current_path, new_path) ~= 0 then
      vim.notify("PKMChangeType: failed to rename file.", vim.log.levels.ERROR)
      return
    end

    -- Write updated frontmatter to new path
    vim.fn.writefile(new_content, new_path)

    -- Propagate rename through citations
    local old_basename = vim.fn.fnamemodify(current_path, ":t:r")
    local new_basename = vim.fn.fnamemodify(new_path, ":t:r")
    require('pkm.citations').update_references_on_rename(old_basename,
    new_basename, existing_fm.title)

    local index = require('pkm.index')
    index.invalidate(current_path)  -- renamed away; remove stale entry
    index.invalidate(new_path)      -- written with new frontmatter; index it

    -- Redirect buffer to new file
    vim.cmd("keepalt file " .. vim.fn.fnameescape(new_path))
    vim.bo.modified = false
    vim.notify(string.format("Changed type: %s → %s", current_type, sel.value), vim.log.levels.INFO)
  end)
end

-- =============================================================================
-- SECTION: Note renaming
-- =============================================================================

--- Prompt for a new name and rename the current consolidated note file.
--- Derives the new filename from the existing number and type prefix.
--- Does not modify the title frontmatter field.
--- Propagates the rename through citations via update_references_on_rename.
---@return nil
function M.rename_note()
  local filepath = vim.fn.expand('%:p')
  local old_stem = vim.fn.fnamemodify(filepath, ':t:r')
  local dir      = vim.fn.fnamemodify(filepath, ':h')

  local number, note_type, name_part = old_stem:match('^(%d+)_([a-z]+)_(.+)$')
  if not number then
    vim.notify('[pkm] not a consolidated note', vim.log.levels.WARN)
    return
  end

  vim.fn.inputsave()
  local input = vim.fn.input('Rename note: ', name_part:gsub('_', ' '))
  vim.fn.inputrestore()
  if not input or input == '' then return end

  local safe_name    = sanitize_title(input)
  local new_filename = string.format('%04d_%s_%s.md', tonumber(number), note_type, safe_name)
  local new_filepath = utils.join(dir, new_filename)

  if new_filepath:gsub('\\', '/') == filepath:gsub('\\', '/') then return end

  if vim.fn.filereadable(new_filepath) == 1 then
    vim.notify('[pkm] cannot rename: target already exists: ' .. new_filename, vim.log.levels.ERROR)
    return
  end

  if vim.fn.rename(filepath, new_filepath) ~= 0 then
    vim.notify('[pkm] rename failed', vim.log.levels.ERROR)
    return
  end

  local index = require('pkm.index')
  index.invalidate(filepath)
  index.invalidate(new_filepath)

  vim.cmd('keepalt file ' .. vim.fn.fnameescape(new_filepath))
  vim.bo.modified = false

  -- Use frontmatter title as display title if set; otherwise derive from new stem.
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local fm, _ = yaml.parse_frontmatter(lines)
  local display_title = (fm and type(fm.title) == 'string' and fm.title ~= '')
                        and fm.title
                        or safe_name:gsub('_', ' ')

  local new_stem = vim.fn.fnamemodify(new_filepath, ':t:r')
  require('pkm.citations').update_references_on_rename(old_stem, new_stem, display_title)
  vim.notify('[pkm] renamed to: ' .. new_filename, vim.log.levels.INFO)
end

-- =============================================================================
-- SECTION: Navigation
-- =============================================================================
--- Insert a [[wiki-link]] to another note at the current cursor position.
--- Searches only the consolidated folder. Uses vim.ui.select for picking.
function M.link_to_note()
  local source_path = vim.fn.expand("%:p")
  if source_path == "" then
    vim.notify("Cannot link from unnamed buffer", vim.log.levels.WARN)
    return
  end
  
  -- Get all notes
  local consolidated_path = utils.join(config.root_path, config.folders.consolidated)
  local files = vim.fn.glob(consolidated_path .. utils.sep .. "*.md", false, true)
  
  local notes = {}
  for _, file in ipairs(files) do
    if file ~= source_path then
      local basename = vim.fn.fnamemodify(file, ":t:r")
      local number, note_type, name = basename:match("^(%d+)_([a-z]+)_(.+)$")
      
      if number and note_type and name then
        local display_name = string.format("[%s%s] %s", note_type, number,
        require('pkm.citations').get_note_title(file))
        
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
    
    local _, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local new_line = line:sub(1, col) .. link .. line:sub(col + 1)
    vim.api.nvim_set_current_line(new_line)
    
    vim.notify("Linked to: " .. selected.basename, vim.log.levels.INFO)
  end)
end

--- Open the note linked under the cursor via [[wiki-link]] syntax.
--- Searches consolidated, journal, and scratchpad folders in that order.
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
    utils.join(config.root_path, config.folders.consolidated, link_target .. ".md"),
    utils.join(config.root_path, config.folders.journal, link_target .. ".md"),
    utils.join(config.root_path, config.folders.scratchpad, link_target .. ".md"),
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

--- Show all notes that contain a [[wiki-link]] to the current note.
--- Searches all three PKM folders. Opens selected backlink with vim.ui.select.
function M.show_backlinks()
  local current_path = vim.fn.expand("%:p")
  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end
  
  local current_basename = vim.fn.fnamemodify(current_path, ":t:r")
  
  local search_paths = {
    utils.join(config.root_path, config.folders.consolidated),
    utils.join(config.root_path, config.folders.journal),
    utils.join(config.root_path, config.folders.scratchpad),
  }
  
  local backlinks = {}
  
  for _, search_path in ipairs(search_paths) do
    local files = vim.fn.glob(search_path .. utils.sep .. "*.md", false, true)
    
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
            display = require('pkm.citations').get_note_title(file),
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

-- =============================================================================
-- SECTION: Import
-- =============================================================================
--- Import an external file into the PKM consolidated folder.
--- Preserves existing frontmatter fields, prompts for type and title,
--- generates a new numbered filename, and optionally deletes the original.
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
      local target_path = utils.join(config.root_path, config.folders.consolidated, filename)
      utils.ensure_dir(vim.fn.fnamemodify(target_path, ":h"))

      -- Prevent overwrite
      if vim.fn.filereadable(target_path) == 1 then
         vim.notify("Cannot import: ID collision or file exists (" .. filename .. ")", vim.log.levels.ERROR)
         return
      end

      -- Generate New Frontmatter
      local template_type = (selected_type == "bib") and "bibliography" or
      selected_type == "agg" and "agg" or "note"

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
      require('pkm.index').invalidate(target_path)

      if current_path ~= "" and vim.fn.filereadable(current_path) == 1 then
        vim.ui.select({"Delete original", "Keep original"}, { prompt = "Import successful. Original file:" }, function(choice)
            if choice == "Delete original" then
                vim.fn.delete(current_path)
                require('pkm.index').invalidate(current_path)
            end
            vim.cmd("edit " .. vim.fn.fnameescape(target_path))
        end)
      else
        vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      end

      vim.notify("Imported: " .. filename, vim.log.levels.INFO)
    end)
  end)
end

return M
