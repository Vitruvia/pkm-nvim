-- lua/pkm/init.lua
-- UPDATED for plugin use
local M = {}

-- Detect OS once at module load
local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
local is_wsl = vim.fn.has('wsl') == 1

-- Configuration with cross-platform defaults
M.config = {
  -- Auto-detect root path based on OS
  root_path = (function()
    if is_windows then
      return vim.fn.expand('~/Documents/Notes')
    elseif is_wsl then
      -- WSL: Default to Windows user directory
      local username = vim.fn.getenv('USER')
      return '/mnt/c/Users/' .. username .. '/Documents/Notes'
    else
      return vim.fn.expand('~/Documents/Notes')
    end
  end)(),
  
  folders = {
    scratchpad = "01-Scratchpad",
    journal = "02-Journal",
    consolidated = "03-Consolidated",
  },

  sync = {
    enabled = true,
    auto_rename = true,
    auto_update_citations = true,
    auto_sync_on_save = true,
    validate_on_sync = true,
    notify_changes = true,
  }, 

  frontmatter_templates = {
    consolidated = {
      title = "", 
      author = "", 
      created_on = "ISO8601", 
      last_updated_on = "ISO8601",
      tags = {}, 
      status = "draft",
      cites = {notes = {}, bib = {}},
      cited_by = {notes = {}, bib = {}},
    },
    journal = {
      created_on = "ISO8601", 
      last_updated_on = "ISO8601", 
      author = "", 
      tags = {},
      location = nil,
      cites = {notes = {}, bib = {}},
      cited_by = {notes = {}, bib = {}},
    },
    bibliography = {
      title = "", 
      source_author = "", 
      note_author = "", 
      created_on = "ISO8601",
      last_updated_on = "ISO8601", 
      citation = "", 
      source_type = "book",
      source_location = "", 
      tags = {},
      cites = {notes = {}, bib = {}},
      cited_by = {notes = {}, bib = {}},
    },
    scratchpad = {
      created_on = "ISO8601", 
      last_updated_on = "ISO8601",
      cites = {notes = {}, bib = {}},
      cited_by = {notes = {}, bib = {}},
    },
  },
  
  citation = {
    inline_format = "%s[%s]",
    auto_number = true,
  },
  
  timestamp = {
    unknown_time_marker = "99-99-99", 
    default_format = "full", 
    auto_timestamp = true,
    prompt_on_create = false,
    formats = {
      full = "%Y-%m-%d_%H-%M-%S", 
      date_time = "%Y-%m-%d_%H-%M",
      date_only = "%Y-%m-%d", 
      date_unknown = "%Y-%m-%d_99-99-99",
    },
  },
  
  user = {
    name = "", 
    email = "", 
    institution = "",
  },
  
  keymaps = {},
}

-- Load submodules (lazy loaded)
local yaml = nil
local timestamp = nil
local citations = nil
local notes = nil
local journal = nil
local ui = nil

local function load_modules()
  if not yaml then
    yaml = require('pkm.yaml')
    timestamp = require('pkm.timestamp')
    citations = require('pkm.citations')
    notes = require('pkm.notes')
    journal = require('pkm.journal')
    ui = require('pkm.ui')
  end
end

--- Setup function to initialize the PKM system
--- @param user_config table|nil User configuration
function M.setup(user_config)
  -- Deep merge user config
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
  
  -- Fill in author fields if user.name is provided
  if M.config.user.name and M.config.user.name ~= "" then
    M.config.frontmatter_templates.consolidated.author = M.config.user.name
    M.config.frontmatter_templates.journal.author = M.config.user.name
    M.config.frontmatter_templates.bibliography.note_author = M.config.user.name
  end
  
  -- Load and setup all modules
  load_modules()
  
  yaml.setup(M.config)
  timestamp.setup(M.config)
  citations.setup(M.config)
  notes.setup(M.config)
  journal.setup(M.config)
  ui.setup(M.config)

  -- Register commands
  M.register_commands()

  -- Setup keymaps if provided
  if M.config.keymaps and next(M.config.keymaps) then
    M.setup_keymaps(M.config.keymaps)
  end

  -- Setup sync if enabled
  if M.config.sync.enabled then
    if M.config.sync.auto_sync_on_save then
      M.setup_sync_autocmds()
    else
      M.setup_basic_sync_autocmds()
    end
  end
  
  vim.notify("PKM System initialized", vim.log.levels.INFO)
end

--- Register all PKM commands
function M.register_commands()
  -- Note creation commands
  vim.api.nvim_create_user_command("PKMNewNote", function(opts)
    local note_type = opts.args
    if note_type == "" then note_type = nil end
    notes.create_new_note(note_type)
  end, { nargs = "?", complete = function() return {"agg", "note", "bib"} end, desc = "Create new consolidated note" })
  
  vim.api.nvim_create_user_command("PKMNewJournal", function() journal.create_entry(true) end, { desc = "Create journal entry with current time" })
  vim.api.nvim_create_user_command("PKMNewJournalCustom", function() journal.create_entry_custom() end, { desc = "Create journal entry with custom time" })
  vim.api.nvim_create_user_command("PKMNewScratchpad", function() notes.create_scratchpad() end, { desc = "Create new scratchpad" })
  vim.api.nvim_create_user_command("PKMQuickCapture", function() notes.quick_capture() end, { desc = "Quick capture to scratchpad" })
  vim.api.nvim_create_user_command("PKMConvertNote", function() notes.convert_note() end, { desc = "Convert note type" })
  
  -- Citation commands
  vim.api.nvim_create_user_command("PKMInsertCitation", function() citations.insert_citation() end, { desc = "Insert citation" })
  vim.api.nvim_create_user_command("PKMUpdateReferences", function() citations.update_references() end, { desc = "Update cites list from text" })
  vim.api.nvim_create_user_command("PKMGotoCitation", function() citations.goto_citation() end, { desc = "Go to citation source" })
  vim.api.nvim_create_user_command("PKMShowCitationPreview", function() citations.show_preview() end, { desc = "Show citation preview" })
  
  -- Navigation commands
  vim.api.nvim_create_user_command("PKMLinkNote", function() notes.link_to_note() end, { desc = "Link to another note" })
  vim.api.nvim_create_user_command("PKMFollowLink", function() notes.follow_link() end, { desc = "Follow link under cursor" })
  vim.api.nvim_create_user_command("PKMBacklinks", function() notes.show_backlinks() end, { desc = "Show backlinks to current note" })
  
  -- Search commands
  vim.api.nvim_create_user_command("PKMSearch", function(opts) ui.search_notes(opts.args) end, { nargs = "?", desc = "Search across all notes" })
  vim.api.nvim_create_user_command("PKMBrowseTags", function() ui.browse_tags() end, { desc = "Browse notes by tags" })
  vim.api.nvim_create_user_command("PKMRecentJournals", function() journal.list_recent(10) end, { desc = "List recent journal entries" })
  
  -- Frontmatter commands
  vim.api.nvim_create_user_command("PKMUpdateFrontmatter", function() yaml.update_frontmatter() end, { desc = "Update YAML frontmatter" })
  vim.api.nvim_create_user_command("PKMValidateFrontmatter", function() yaml.validate_frontmatter() end, { desc = "Validate YAML frontmatter" })
  vim.api.nvim_create_user_command("PKMUpdateTimestamp", function() yaml.update_last_modified() end, { desc = "Update last_updated_on timestamp" })
  
  -- Utility commands
  vim.api.nvim_create_user_command("PKMStats", function() M.show_stats() end, { desc = "Show PKM statistics" })
  vim.api.nvim_create_user_command("PKMToggleAutoTimestamp", function()
    M.config.timestamp.auto_timestamp = not M.config.timestamp.auto_timestamp
    vim.notify("Auto timestamp: " .. (M.config.timestamp.auto_timestamp and "ON" or "OFF"), vim.log.levels.INFO)
  end, { desc = "Toggle automatic timestamps" })
  vim.api.nvim_create_user_command("PKMSetDefaultFormat", function(opts)
    local format = opts.args
    if format == "full" or format == "date_time" or format == "date_only" then
      M.config.timestamp.default_format = format
      vim.notify("Default timestamp format: " .. format, vim.log.levels.INFO)
    else
      vim.notify("Invalid format. Use: full, date_time, or date_only", vim.log.levels.ERROR)
    end
  end, { nargs = 1, complete = function() return {"full", "date_time", "date_only"} end, desc = "Set default timestamp format" })
  
  -- Cleanup and sync commands
  vim.api.nvim_create_user_command("PKMCleanupFrontmatter", function() citations.cleanup_frontmatter() end, { desc = "Remove corrupted frontmatter keys" })
  
  vim.api.nvim_create_user_command("PKMSync", function()
    local start_time = vim.loop.hrtime()
    citations.update_references()
    citations.cleanup_frontmatter()
    local elapsed = (vim.loop.hrtime() - start_time) / 1e6
    vim.notify(string.format("Synchronized all references (%.1fms)", elapsed), vim.log.levels.INFO)
  end, { desc = "Synchronize and validate all references" })

  vim.api.nvim_create_user_command("PKMToggleAutoSync", function()
    M.config.sync.auto_sync_on_save = not M.config.sync.auto_sync_on_save
    local status = M.config.sync.auto_sync_on_save and "enabled" or "disabled"
    vim.notify("Auto-sync on save: " .. status, vim.log.levels.INFO)
    vim.api.nvim_clear_autocmds({group = "PKMSync"})
    if M.config.sync.auto_sync_on_save then
      M.setup_sync_autocmds()
    else
      M.setup_basic_sync_autocmds()
    end
  end, { desc = "Toggle automatic reference synchronization" })

  vim.api.nvim_create_user_command("PKMValidate", function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local fm, content_start = yaml.parse_frontmatter(lines)
    if not fm then vim.notify("No frontmatter to validate.", vim.log.levels.WARN); return end

    local all_items = citations.get_citable_items_map()
    local report = {
      valid_cites = 0, stale_cites = {},
      valid_cited_by = 0, stale_cited_by = {},
      broken_inline = {}
    }

    if fm.cites then
      for _, group in ipairs({"notes", "bib"}) do
        if fm.cites[group] then
          for _, entry in ipairs(fm.cites[group]) do
            if type(entry) == "table" and entry.identifier then
              if not (all_items[entry.identifier] and vim.fn.filereadable(all_items[entry.identifier].path) == 1) then
                table.insert(report.stale_cites, { group = group, id = entry.identifier, title = entry.title or "unknown" })
              else
                report.valid_cites = report.valid_cites + 1
              end
            end
          end
        end
      end
    end

    if fm.cited_by then
      for _, group in ipairs({"notes", "bib"}) do
        if fm.cited_by[group] then
          for _, entry in ipairs(fm.cited_by[group]) do
            if type(entry) == "table" and entry.identifier then
              if not (all_items[entry.identifier] and vim.fn.filereadable(all_items[entry.identifier].path) == 1) then
                table.insert(report.stale_cited_by, { group = group, id = entry.identifier, title = entry.title or "unknown" })
              else
                report.valid_cited_by = report.valid_cited_by + 1
              end
            end
          end
        end
      end
    end

    for i = content_start, #lines do
      for match in lines[i]:gmatch("%[%[([^%]]+)%]%]") do
        local found = false
        for _, item in pairs(all_items) do
          if item.basename == match and vim.fn.filereadable(item.path) == 1 then
            found = true
            break
          end
        end
        if not found then table.insert(report.broken_inline, { line = i, link = match }) end
      end
    end

    local lines_report = {
      "=== Reference Validation Report ===", "",
      string.format("Valid citations: %d", report.valid_cites),
      string.format("Valid backlinks: %d", report.valid_cited_by), ""
    }
    if #report.stale_cites > 0 then
      table.insert(lines_report, string.format("Stale citations (%d):", #report.stale_cites))
      for _, stale in ipairs(report.stale_cites) do table.insert(lines_report, string.format("  - %s/%s: %s", stale.group, stale.id, stale.title)) end
      table.insert(lines_report, "")
    end
    if #report.stale_cited_by > 0 then
      table.insert(lines_report, string.format("Stale backlinks (%d):", #report.stale_cited_by))
      for _, stale in ipairs(report.stale_cited_by) do table.insert(lines_report, string.format("  - %s/%s: %s", stale.group, stale.id, stale.title)) end
      table.insert(lines_report, "")
    end
    if #report.broken_inline > 0 then
      table.insert(lines_report, string.format("Broken inline links (%d):", #report.broken_inline))
      for _, broken in ipairs(report.broken_inline) do table.insert(lines_report, string.format("  - Line %d: [[%s]]", broken.line, broken.link)) end
      table.insert(lines_report, "")
    end
    if #report.stale_cites == 0 and #report.stale_cited_by == 0 and #report.broken_inline == 0 then
      table.insert(lines_report, "✓ All references are valid!")
    else
      table.insert(lines_report, "\nRun :PKMSync to clean up stale references")
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_report)
    local width, height = 80, math.min(#lines_report + 2, 25)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor', width = width, height = height,
      col = (vim.o.columns - width) / 2, row = (vim.o.lines - height) / 2,
      style = 'minimal', border = 'rounded', title = " PKM Validation Report ", title_pos = 'center',
    })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
  end, { desc = "Validate reference integrity" })
  
  vim.api.nvim_create_user_command("PKMDeleteNote", function() M.delete_note_safely() end, { desc = "Delete note and clean up references" })
end

--- Setup key mappings
function M.setup_keymaps(keymaps)
  local function map(mode, lhs, rhs, opts)
    opts = opts or {}
    opts.silent = opts.silent ~= false
    vim.keymap.set(mode, lhs, rhs, opts)
  end
  
  if keymaps.new_note then map('n', keymaps.new_note, ':PKMNewNote<CR>', { desc = "New note" }) end
  if keymaps.new_journal then map('n', keymaps.new_journal, ':PKMNewJournal<CR>', { desc = "New journal (current time)" }) end
  if keymaps.new_scratchpad then map('n', keymaps.new_scratchpad, ':PKMNewScratchpad<CR>', { desc = "New scratchpad" }) end
  if keymaps.quick_capture then map('n', keymaps.quick_capture, ':PKMQuickCapture<CR>', { desc = "Quick capture" }) end
  if keymaps.convert_note then map('n', keymaps.convert_note, ':PKMConvertNote<CR>', { desc = "Convert note type" }) end
  if keymaps.insert_citation then map('n', keymaps.insert_citation, ':PKMInsertCitation<CR>', { desc = "Insert citation" }) end
  if keymaps.goto_citation then map('n', keymaps.goto_citation, ':PKMGotoCitation<CR>', { desc = "Go to citation" }) end
  if keymaps.preview_citation then map('n', keymaps.preview_citation, ':PKMShowCitationPreview<CR>', { desc = "Preview citation" }) end
  if keymaps.link_note then map('n', keymaps.link_note, ':PKMLinkNote<CR>', { desc = "Link note" }) end
  if keymaps.follow_link then map('n', keymaps.follow_link, ':PKMFollowLink<CR>', { desc = "Follow link" }) end
  if keymaps.backlinks then map('n', keymaps.backlinks, ':PKMBacklinks<CR>', { desc = "Show backlinks" }) end
  if keymaps.search then map('n', keymaps.search, ':PKMSearch<CR>', { desc = "Search notes" }) end
  if keymaps.browse_tags then map('n', keymaps.browse_tags, ':PKMBrowseTags<CR>', { desc = "Browse tags" }) end
  if keymaps.recent_journals then map('n', keymaps.recent_journals, ':PKMRecentJournals<CR>', { desc = "Recent journals" }) end
  if keymaps.delete_note then map('n', keymaps.delete_note, ':PKMDeleteNote<CR>', { desc = "Delete note safely" }) end
end

--- Setup autocmds for bidirectional filename-YAML sync
function M.setup_sync_autocmds()
  local augroup = vim.api.nvim_create_augroup("PKMSync", { clear = true })
  
  -- Sync on save (includes reference updates)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      
      -- Only process PKM files
      if not filepath:find(M.config.root_path, 1, true) then
        return
      end
      
      -- ============================ START OF FINAL FIX ============================
      -- Schedule the ENTIRE block of post-save logic to run on the next event loop tick.
      -- This completely decouples our logic from the save event, preventing all race conditions.
      vim.schedule(function()
        -- STEP 1: Update the timestamp on disk first.
        local lines = vim.fn.readfile(filepath)
        local frontmatter, content_start = yaml.parse_frontmatter(lines)
        
        if frontmatter then
          frontmatter.last_updated_on = timestamp.to_iso8601()
          yaml.save_frontmatter(frontmatter, content_start, filepath)
        end
        
        -- STEP 2: Sync the filename. This might reload the buffer.
        if filepath:find(M.config.folders.consolidated, 1, true) then
          notes.sync_filename_on_save()
        end
        if filepath:find(M.config.folders.journal, 1, true) then
          journal.sync_filename_on_save()
        end

        -- STEP 3: Sync references. This now runs on the correct, potentially reloaded buffer.
        if M.config.sync.auto_sync_on_save then
          citations.update_references()
        end

        -- STEP 4: Tell Neovim to check for external changes. 'autoread' will handle the reload.
        -- This is now the VERY LAST step, ensuring all disk changes are complete.
        vim.cmd("checktime")
      end)
      -- ============================= END OF FINAL FIX =============================
    end,
    desc = "PKM: Auto-sync on save"
  })
  
  -- Sync YAML when file is renamed externally (This part is unchanged)
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup,
    pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      if not filepath:find(M.config.root_path, 1, true) then return end
      if filepath:find(M.config.folders.consolidated, 1, true) then notes.sync_yaml_on_rename() end
      if filepath:find(M.config.folders.journal, 1, true) then journal.sync_yaml_on_rename() end
    end,
    desc = "PKM: Sync YAML when file is renamed"
  })
end

--- Setup autocmds without auto-sync
function M.setup_basic_sync_autocmds()
  local augroup = vim.api.nvim_create_augroup("PKMSync", { clear = true })
  
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      if not filepath:find(M.config.root_path, 1, true) then return end
      
      yaml.update_last_modified()
      
      if filepath:find(M.config.folders.consolidated, 1, true) then notes.sync_filename_on_save() end
      if filepath:find(M.config.folders.journal, 1, true) then journal.sync_filename_on_save() end
    end,
    desc = "PKM: Basic sync on save (no auto-update)"
  })
end

--- Delete note safely
function M.delete_note_safely()
  local filepath = vim.fn.expand("%:p")
  if filepath == "" or not filepath:find(M.config.root_path, 1, true) then
    vim.notify("Not a valid PKM note.", vim.log.levels.ERROR)
    return
  end
  
  local filename = vim.fn.fnamemodify(filepath, ":t")
  vim.fn.inputsave()
  local confirm = vim.fn.input(string.format("Delete '%s' and all references? (yes/no): ", filename))
  vim.fn.inputrestore()
  
  if confirm:lower() ~= "yes" then
    vim.notify("Deletion cancelled.", vim.log.levels.INFO)
    return
  end
  
  citations.cleanup_deleted_note(filepath)
  vim.cmd("bdelete!")
  
  if vim.fn.delete(filepath) == 0 then
    vim.notify("Note deleted and references cleaned up.", vim.log.levels.INFO)
  else
    vim.notify("Failed to delete file.", vim.log.levels.ERROR)
  end
end

--- Show PKM statistics
function M.show_stats()
  local stats = {
    total_notes = 0, total_journals = 0, total_scratchpads = 0,
    total_citations = 0, notes_by_status = {}, notes_by_tag = {},
  }
  
  local function collect_from_folder(folder_path, note_type)
    local files = vim.fn.glob(folder_path .. "/*.md", false, true)
    
    for _, file in ipairs(files) do
      if note_type == "journal" then stats.total_journals = stats.total_journals + 1
      elseif note_type == "scratchpad" then stats.total_scratchpads = stats.total_scratchpads + 1
      else
        stats.total_notes = stats.total_notes + 1
        local content = vim.fn.readfile(file)
        local frontmatter, _ = yaml.parse_frontmatter(content)
        if frontmatter then
          local status = frontmatter.status or "unknown"
          stats.notes_by_status[status] = (stats.notes_by_status[status] or 0) + 1
          if frontmatter.tags and type(frontmatter.tags) == 'table' then
            for _, tag in ipairs(frontmatter.tags) do
              stats.notes_by_tag[tag] = (stats.notes_by_tag[tag] or 0) + 1
            end
          end
          if frontmatter.cites then
             if frontmatter.cites.notes then stats.total_citations = stats.total_citations + #frontmatter.cites.notes end
             if frontmatter.cites.bib then stats.total_citations = stats.total_citations + #frontmatter.cites.bib end
          end
        end
      end
    end
  end
  
  local root = M.config.root_path
  local path_sep = package.config:sub(1, 1)
  collect_from_folder(root .. path_sep .. M.config.folders.consolidated, "note")
  collect_from_folder(root .. path_sep .. M.config.folders.journal, "journal")
  collect_from_folder(root .. path_sep .. M.config.folders.scratchpad, "scratchpad")
  
  ui.show_stats_window(stats)
end

-- Export submodules for advanced users
M.yaml = function() return yaml or require('pkm.yaml') end
M.timestamp = function() return timestamp or require('pkm.timestamp') end
M.citations = function() return citations or require('pkm.citations') end
M.notes = function() return notes or require('pkm.notes') end
M.journal = function() return journal or require('pkm.journal') end
M.ui = function() return ui or require('pkm.ui') end

return M
