-- lua/pkm/init.lua
local M = {}

local default_config = {
  -- Default to home, but this should be overwritten by your setup() call
  root_path = vim.fn.expand('~/Notes'),
  
  folders = {
    consolidated = "03-Consolidated",
    journal = "02-Journal",
    scratchpad = "01-Scratchpad",
    templates = "templates",
  },
  
  sync = { enabled = true, auto_sync_on_save = true },

  frontmatter_templates = {
    consolidated = {
      title = "", author = "", created_on = "ISO8601", last_updated_on = "ISO8601",
      tags = {}, status = "draft", cites = {notes = {}, bib = {}, journal = {}}, cited_by = {notes = {}, bib = {}, journal = {}},
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
      cites = {notes = {}, bib = {}, journal = {}}, cited_by = {notes = {}, bib = {}, journal = {}},
    },
  },
  
  timestamp = { default_format = "full", auto_timestamp = true },
  user = { name = "", email = "" },

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
  }
}

M.config = default_config

function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

  -- Validate Root Path
  local root = M.config.root_path
  if vim.fn.isdirectory(root) == 0 then
    -- Try to expand if it contains ~
    root = vim.fn.expand(root)
    M.config.root_path = root
  end
  
  if vim.fn.isdirectory(root) == 0 then
    vim.notify("PKM Error: Root path does not exist: " .. root, vim.log.levels.ERROR)
  else
    -- Optional: confirm loaded path (comment out once working)
    -- vim.notify("PKM Root: " .. root, vim.log.levels.INFO)
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
  vim.api.nvim_create_user_command('PKMNewNote', function(opts) require('pkm.notes').create_new_note(opts.args ~= "" and opts.args or nil) end, { nargs = "?" })
  vim.api.nvim_create_user_command('PKMNewJournal', function() require('pkm.journal').create_entry(true) end, {})
  vim.api.nvim_create_user_command('PKMNewScratchpad', function() require('pkm.notes').create_scratchpad() end, {})
  vim.api.nvim_create_user_command('PKMDeleteNote', function() M.delete_note_safely() end, {})
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

  if M.config.sync.enabled then M.setup_sync_autocmds() end
end

function M.setup_sync_autocmds()
  local augroup = vim.api.nvim_create_augroup("PKMSync", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      if not filepath:find(M.config.root_path, 1, true) then return end
      vim.schedule(function()
        local yaml = require('pkm.yaml')
        local timestamp = require('pkm.timestamp')
        local notes = require('pkm.notes')
        local journal = require('pkm.journal')
        local citations = require('pkm.citations')

        local lines = vim.fn.readfile(filepath)
        local frontmatter, content_start = yaml.parse_frontmatter(lines)
        if frontmatter then
          frontmatter.last_updated_on = timestamp.to_iso8601()
          yaml.save_frontmatter(frontmatter, content_start, filepath)
        end
        if filepath:find(M.config.folders.consolidated, 1, true) then notes.sync_filename_on_save() end
        if filepath:find(M.config.folders.journal, 1, true) then journal.sync_filename_on_save() end
        if M.config.sync.auto_sync_on_save then citations.update_references() end
        vim.cmd("checktime")
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      if not filepath:find(M.config.root_path, 1, true) then return end
      if filepath:find(M.config.folders.consolidated, 1, true) then require('pkm.notes').sync_yaml_on_rename() end
      if filepath:find(M.config.folders.journal, 1, true) then require('pkm.journal').sync_yaml_on_rename() end
    end,
  })
end

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
  if confirm:lower() ~= "yes" then return end
  require('pkm.citations').cleanup_deleted_note(filepath)
  vim.cmd("bdelete!")
  vim.fn.delete(filepath)
  vim.notify("Note deleted.", vim.log.levels.INFO)
end

return M
