-- lua/pkm/init.lua
local M = {}

local default_config = {
  root_path = vim.fn.expand('~/Notes'),
  folders = {
    consolidated = "03-Consolidated",
    journal = "02-Journal",
    scratchpad = "01-Scratchpad",
    templates = "templates",
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

  -- Initialize Modules (Order matters)
  -- Utils first
  require('pkm.timestamp').setup(M.config)
  require('pkm.yaml').setup(M.config)
  
  -- Core modules next
  require('pkm.citations').setup(M.config)
  require('pkm.templates').setup(M.config)
  require('pkm.journal').setup(M.config)
  require('pkm.notes').setup(M.config)
  require('pkm.ui').setup(M.config)
  
  -- Legacy core (optional, but keeping for safety if other things depend on it)
  require('pkm.core').setup(M.config)

  -- --- COMMANDS ---
  
  -- Creation (FIXED: Pointing to specific modules instead of core.lua)
  vim.api.nvim_create_user_command('PKMNewNote', function(opts) 
    require('pkm.notes').create_new_note(opts.args ~= "" and opts.args or nil) 
  end, { nargs = "?" })
  
  vim.api.nvim_create_user_command('PKMNewJournal', function() 
    require('pkm.journal').create_entry(true) -- Use journal.lua for correct format
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
