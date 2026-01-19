-- lua/pkm/init.lua
local M = {}

-- Define defaults including the templates needed by yaml.lua
local default_config = {
  root_path = vim.fn.expand('~/Notes'),
  
  folders = {
    consolidated = "03-Consolidated",
    journal = "02-Journal",
    scratchpad = "01-Scratchpad",
    templates = "templates",
  },
  
  -- FIXED: Added missing templates to prevent yaml.lua crash
  frontmatter_templates = {
    consolidated = {
      title = "", 
      author = "", 
      created_on = "ISO8601", 
      last_updated_on = "ISO8601",
      tags = {}, 
      status = "draft",
      cites = {notes = {}, bib = {}, journal = {}},
      cited_by = {notes = {}, bib = {}, journal = {}},
    },
    journal = {
      created_on = "ISO8601", 
      last_updated_on = "ISO8601", 
      author = "", 
      tags = {},
      cites = {notes = {}, bib = {}, journal = {}},
      cited_by = {notes = {}, bib = {}, journal = {}},
    },
    bibliography = {
      title = "", 
      source_author = "", 
      note_author = "", 
      created_on = "ISO8601",
      last_updated_on = "ISO8601", 
      citation = "", 
      source_type = "book", 
      tags = {},
      cites = {notes = {}, bib = {}, journal = {}},
      cited_by = {notes = {}, bib = {}, journal = {}},
    },
    scratchpad = {
      created_on = "ISO8601", 
      last_updated_on = "ISO8601",
      cites = {notes = {}, bib = {}, journal = {}},
      cited_by = {notes = {}, bib = {}, journal = {}},
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
    search = "<leader>nf",
    browse_tags = "<leader>nt",
    insert_citation = "<leader>nc",
  }
}

M.config = default_config

function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

  -- Inject user name into templates if provided
  if M.config.user and M.config.user.name ~= "" then
    if M.config.frontmatter_templates.consolidated then
        M.config.frontmatter_templates.consolidated.author = M.config.user.name
    end
    if M.config.frontmatter_templates.journal then
        M.config.frontmatter_templates.journal.author = M.config.user.name
    end
  end

  -- Initialize Modules
  require('pkm.timestamp').setup(M.config)
  require('pkm.yaml').setup(M.config)
  require('pkm.citations').setup(M.config)
  require('pkm.templates').setup(M.config)
  require('pkm.journal').setup(M.config)
  require('pkm.notes').setup(M.config)
  require('pkm.ui').setup(M.config)
  
  -- REMOVED: require('pkm.core') -- Core is obsolete

  -- --- COMMANDS ---
  
  -- Creation
  vim.api.nvim_create_user_command('PKMNewNote', function(opts) 
    require('pkm.notes').create_new_note(opts.args ~= "" and opts.args or nil) 
  end, { nargs = "?" })
  
  vim.api.nvim_create_user_command('PKMNewJournal', function() 
    require('pkm.journal').create_entry(true) 
  end, {})
  
  -- Search & Navigation
  vim.api.nvim_create_user_command('PKMSearch', function() require('pkm.telescope').search_notes() end, {})
  vim.api.nvim_create_user_command('PKMTags', function() require('pkm.telescope').browse_tags() end, {})
  vim.api.nvim_create_user_command('PKMFind', function() require('pkm.telescope').find_notes() end, {})
  
  -- Citations & Utils
  vim.api.nvim_create_user_command('PKMInsertCitation', function() require('pkm.telescope').insert_citation_picker() end, {})
  vim.api.nvim_create_user_command('PKMUpdateReferences', function() require('pkm.citations').update_references() end, {})
  vim.api.nvim_create_user_command('PKMApplyTemplate', function() require('pkm.templates').apply_template() end, {})

  -- --- KEYMAPS ---
  local k = M.config.keymaps
  local function map(lhs, cmd, desc)
    if lhs then 
      vim.keymap.set('n', lhs, cmd, { desc = "PKM: " .. desc, silent = true }) 
    end
  end

  map(k.new_note, "<cmd>PKMNewNote<cr>", "New Note")
  map(k.new_journal, "<cmd>PKMNewJournal<cr>", "New Journal")
  map(k.search, "<cmd>PKMSearch<cr>", "Search Content")
  map(k.browse_tags, "<cmd>PKMTags<cr>", "Browse Tags") 
  map(k.insert_citation, "<cmd>PKMInsertCitation<cr>", "Insert Citation")
  map(k.quick_capture, "<cmd>PKMNewNote<cr>", "Quick Capture")
end

return M
