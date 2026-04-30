-- lua/pkm/init.lua
local M = {}

local default_config = {
  -- Default is nil so we can detect if user provided input
  root_path = nil,
  
  folders = {
    consolidated = "03-Consolidated",
    journal = "02-Journal",
    scratchpad = "01-Scratchpad",
    templates = "templates",
  },
  
  sync = {
    enabled = true,
    auto_sync_on_save = true,
  },

  frontmatter_templates = {
    consolidated = {
      title = "", author = "", created_on = "ISO8601", last_updated_on = "ISO8601",
      tags = {}, cites = {notes = {}, bib = {}, journal = {}}, cited_by = {notes = {}, bib = {}, journal = {}},
    },
    journal = {
      created_on = "ISO8601", last_updated_on = "ISO8601", author = "",
      tags = {}, cites = {notes = {}, bib = {}, journal = {}}, cited_by = {notes = {}, bib = {}, journal = {}},
    },
    bibliography = {
      title = "", source_author = "", created_on = "ISO8601", last_updated_on = "ISO8601",
      cites = {notes = {}, bib = {}, journal = {}}, cited_by = {notes = {}, bib = {}, journal = {}},
    },
    scratchpad = {
      created_on = "ISO8601", last_updated_on = "ISO8601",
      tags = {},
      cites = {notes = {}, bib = {}, journal = {}}, cited_by = {notes = {}, bib = {}, journal = {}},
    },
  },
  
  timestamp = {
    default_format = "full",
    auto_timestamp = true,
  },
  
  user = {
    name = "",
    email = "",
  },

  keymaps = {
    new_note = "<leader>nn",
    new_journal = "<leader>nj",
    new_scratchpad = "<leader>ns",
    search = "<leader>nf",
    browse_tags = "<leader>nt",
    insert_citation = "<leader>nc",
    goto_citation = "<leader>ng",
    delete_note = "<leader>nd",
    link_note = "<leader>nl",
    follow_link = "gf",
    backlinks = "<leader>nb",
    quick_capture = "<leader>nq",
    import_note = "<leader>ni",
    convert_note = "<leader>nx",
    promote_note = "<leader>np",
  }
}

M.config = default_config

function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

  -- 1. Path Resolution
  if not M.config.root_path then
    M.config.root_path = vim.fn.expand('~/Notes')
  end

  -- Windows Path Normalization (Convert / to \)
  if vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    M.config.root_path = M.config.root_path:gsub("/", "\\")
  end

  -- Validation
  if vim.fn.isdirectory(M.config.root_path) == 0 then
    vim.notify("PKM Critical: Root path does not exist: " .. M.config.root_path, vim.log.levels.ERROR)
  else
    -- Optional debug: vim.notify("PKM Root: " .. M.config.root_path, vim.log.levels.INFO)
  end

  -- Inject user name
  if M.config.user and M.config.user.name ~= "" then
    M.config.frontmatter_templates.consolidated.author = M.config.user.name
    M.config.frontmatter_templates.journal.author = M.config.user.name
  end

  -- Initialize Modules
  require('pkm.timestamp').setup(M.config)
  require('pkm.yaml').setup(M.config)
  require('pkm.citations').setup(M.config)
  require('pkm.templates').setup(M.config)
  require('pkm.journal').setup(M.config)
  require('pkm.notes').setup(M.config)
  require('pkm.ui').setup(M.config)

  -- --- COMMANDS ---
  vim.api.nvim_create_user_command('PKMNewNote', function(opts) 
    require('pkm.notes').create_new_note(opts.args ~= "" and opts.args or nil) 
  end, { nargs = "?" })
  
  vim.api.nvim_create_user_command('PKMNewJournal', function() 
    require('pkm.journal').create_entry(true) 
  end, {})
  
  vim.api.nvim_create_user_command('PKMNewScratchpad', function() 
    require('pkm.notes').create_scratchpad() 
  end, {})
  
  vim.api.nvim_create_user_command('PKMDeleteNote', function() 
    M.delete_note_safely() 
  end, {})

  vim.api.nvim_create_user_command('PKMImport', function() 
      require('pkm.notes').import_note() 
  end, { desc = "Import current file into PKM system" })
   
  vim.api.nvim_create_user_command('PKMToggleAutoSync', function()
     M.config.sync.auto_sync_on_save = not M.config.sync.auto_sync_on_save
     local status = M.config.sync.auto_sync_on_save and "enabled" or "disabled"
     vim.notify("Auto-sync on save: " .. status, vim.log.levels.INFO)
     vim.api.nvim_clear_autocmds({ group = "PKMSync" })
     if M.config.sync.enabled then M.setup_sync_autocmds() end
   end, { desc = "Toggle automatic reference synchronization" })

  vim.api.nvim_create_user_command('PKMConvertNote', function()
    require('pkm.notes').convert_note()
  end, { desc = "Convert current note to a different type" })
  
  vim.api.nvim_create_user_command('PKMPromote', function()
    require('pkm.notes').promote_note()
  end, { desc = "Promote scratchpad to consolidated note or journal" })

  vim.api.nvim_create_user_command('PKMSearch', function() require('pkm.telescope').search_notes() end, {})
  vim.api.nvim_create_user_command('PKMTags', function() require('pkm.telescope').browse_tags() end, {})
  vim.api.nvim_create_user_command('PKMInsertCitation', function() require('pkm.telescope').insert_citation_picker() end, {})
  vim.api.nvim_create_user_command('PKMGotoCitation', function() require('pkm.citations').goto_citation() end, {})
  vim.api.nvim_create_user_command('PKMUpdateReferences', function() require('pkm.citations').update_references() end, {})
  
  vim.api.nvim_create_user_command('PKMLinkNote', function() require('pkm.notes').link_to_note() end, {})
  vim.api.nvim_create_user_command('PKMFollowLink', function() require('pkm.notes').follow_link() end, {})
  vim.api.nvim_create_user_command('PKMBacklinks', function() require('pkm.notes').show_backlinks() end, {})

  -- --- KEYMAPS ---
  local k = M.config.keymaps
  local function map(lhs, cmd, desc)
    if lhs then vim.keymap.set('n', lhs, cmd, { desc = "PKM: " .. desc, silent = true }) end
  end

  if M.config.keymaps.promote_note then
    vim.keymap.set('n', M.config.keymaps.promote_note,
      function() require('pkm.notes').promote_note() end,
      { noremap = true, silent = true, desc = "PKM: Promote note" })
  end

  map(k.new_note, "<cmd>PKMNewNote<cr>", "New Note")
  map(k.new_journal, "<cmd>PKMNewJournal<cr>", "New Journal")
  map(k.new_scratchpad, "<cmd>PKMNewScratchpad<cr>", "New Scratchpad")
  map(k.delete_note, "<cmd>PKMDeleteNote<cr>", "Delete Note")
  map(k.search, "<cmd>PKMSearch<cr>", "Search Content")
  map(k.browse_tags, "<cmd>PKMTags<cr>", "Browse Tags") 
  map(k.insert_citation, "<cmd>PKMInsertCitation<cr>", "Insert Citation")
  map(k.goto_citation, "<cmd>PKMGotoCitation<cr>", "Goto Citation")
  map(k.link_note, "<cmd>PKMLinkNote<cr>", "Link Note")
  map(k.follow_link, "<cmd>PKMFollowLink<cr>", "Follow Link")
  map(k.backlinks, "<cmd>PKMBacklinks<cr>", "Backlinks")
  map(k.quick_capture, "<cmd>PKMNewNote<cr>", "Quick Capture")
  map(k.import_note, "<cmd>PKMImport<cr>", "Import Note")

  if M.config.sync.enabled then M.setup_sync_autocmds() end
end

function M.setup_sync_autocmds()
  local augroup = vim.api.nvim_create_augroup("PKMSync", { clear = true })
  
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      if not filepath:lower():find(".md") then return end
      
      vim.schedule(function()
        local root = M.config.root_path
        local norm_path = filepath:gsub("\\", "/")
        local norm_root = root:gsub("\\", "/")
        if not norm_path:lower():find(norm_root:lower(), 1, true) then return end

        local yaml = require('pkm.yaml')
        local timestamp = require('pkm.timestamp')
        local notes = require('pkm.notes')
        local journal = require('pkm.journal')
        local citations = require('pkm.citations')

        local lines = vim.fn.readfile(filepath)
        if lines[1] == "---" then
            local frontmatter, content_start = yaml.parse_frontmatter(lines)
            if not frontmatter or (frontmatter.cites and type(frontmatter.cites) ~= "table") then
                vim.notify("PKM Error: Frontmatter corrupted. Sync aborted.", vim.log.levels.ERROR)
                return 
            end
            frontmatter.last_updated_on = timestamp.to_iso8601()
            yaml.save_frontmatter(frontmatter, content_start, filepath)
        end

        if filepath:find(M.config.folders.consolidated, 1, true) then notes.sync_filename_on_save() end
        if filepath:find(M.config.folders.journal, 1, true) then journal.sync_filename_on_save() end
        
        -- FIXED: Pass filepath to update references on DISK, so reloading gets everything
        if M.config.sync.auto_sync_on_save then 
            citations.update_references(filepath) 
        end
        
        vim.cmd("checktime")
      end)
    end,
  })
  
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      local root = M.config.root_path
      local norm_path = filepath:gsub("\\", "/")
      local norm_root = root:gsub("\\", "/")
      if not norm_path:lower():find(norm_root:lower(), 1, true) then return end
      if filepath:find(M.config.folders.consolidated, 1, true) then require('pkm.notes').sync_yaml_on_rename() end
      if filepath:find(M.config.folders.journal, 1, true) then require('pkm.journal').sync_yaml_on_rename() end
    end,
  })
end

function M.delete_note_safely()
  local filepath = vim.fn.expand("%:p")
  local root = M.config.root_path
  
  -- Normalization for comparison
  local norm_path = filepath:gsub("\\", "/")
  local norm_root = root:gsub("\\", "/")

  if filepath == "" or not norm_path:lower():find(norm_root:lower(), 1, true) then
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
  
  require('pkm.citations').cleanup_deleted_note(filepath)
  vim.cmd("bdelete!")
  
  if vim.fn.delete(filepath) == 0 then
    vim.notify("Note deleted.", vim.log.levels.INFO)
  else
    vim.notify("Failed to delete file.", vim.log.levels.ERROR)
  end
end

return M
