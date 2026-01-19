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

  -- Initialize Modules (Order matters for dependencies)
  -- 1. Utils
  require('pkm.timestamp').setup(M.config) -- FIXED: Was missing, required for journal format
  require('pkm.yaml').setup(M.config)
  
  -- 2. Core Logic
  require('pkm.citations').setup(M.config)
  require('pkm.templates').setup(M.config)
  require('pkm.journal').setup(M.config)   -- FIXED: Was missing
  require('pkm.notes').setup(M.config)     -- FIXED: Was missing
  require('pkm.ui').setup(M.config)        -- FIXED: Was missing
  require('pkm.core').setup(M.config)

  -- --- Create Commands ---
  
  -- Creation
  vim.api.nvim_create_user_command('PKMNewNote', function(opts) require('pkm.core').new_note(opts.args) end, { nargs = "?" })
  vim.api.nvim_create_user_command('PKMNewJournal', function() require('pkm.core').new_journal() end, {})
  
  -- Search & Navigation
  vim.api.nvim_create_user_command('PKMSearch', function() require('pkm.telescope').search_notes() end, {})
  vim.api.nvim_create_user_command('PKMTags', function() require('pkm.telescope').browse_tags() end, {})
  vim.api.nvim_create_user_command('PKMFind', function() require('pkm.telescope').find_notes() end, {})
  
  -- Citations & Utils
  vim.api.nvim_create_user_command('PKMInsertCitation', function() require('pkm.telescope').insert_citation_picker() end, {})
  vim.api.nvim_create_user_command('PKMUpdateReferences', function() require('pkm.citations').update_references() end, {})
  vim.api.nvim_create_user_command('PKMApplyTemplate', function() require('pkm.templates').apply_template() end, {})

  -- --- BIND KEYMAPS ---
  local k = M.config.keymaps
  local map = function(lhs, cmd, desc)
    if lhs then vim.keymap.set('n', lhs, cmd, { desc = "PKM: " .. desc, silent = true }) end
  end

  map(k.new_note, "<cmd>PKMNewNote<cr>", "New Note")
  map(k.new_journal, "<cmd>PKMNewJournal<cr>", "New Journal")
  map(k.search, "<cmd>PKMSearch<cr>", "Search Content")
  map(k.browse_tags, "<cmd>PKMTags<cr>", "Browse Tags") 
  map(k.insert_citation, "<cmd>PKMInsertCitation<cr>", "Insert Citation")
  map(k.quick_capture, "<cmd>PKMNewNote<cr>", "Quick Capture")
end

return M
