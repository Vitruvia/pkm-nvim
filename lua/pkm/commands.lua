-- lua/pkm/commands.lua
-- Registers all :PKM* user commands.
-- Called once by init.lua after config is resolved.
-- Modules are required lazily inside each handler.

local M = {}

function M.register()
  --- COMMANDS ---
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

  vim.api.nvim_create_user_command('PKMExport', function()
    require('pkm.export').interactive_export()
  end, { desc = "Filter notes and copy to a folder" })

  vim.api.nvim_create_user_command('PKMSearch', function() require('pkm.telescope').search_notes() end, {})
  vim.api.nvim_create_user_command('PKMTags', function() require('pkm.telescope').browse_tags() end, {})

  vim.api.nvim_create_user_command('PKMMergeTags', function()
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').merge_tags_picker()
    else
      require('pkm.ui').merge_tags_ui()
    end
  end, { desc = "Merge tags across all notes" })

  vim.api.nvim_create_user_command('PKMInsertCitation', function() require('pkm.telescope').insert_citation_picker() end, {})
  vim.api.nvim_create_user_command('PKMGotoCitation', function() require('pkm.citations').goto_citation() end, {})
  vim.api.nvim_create_user_command('PKMUpdateReferences', function() require('pkm.citations').update_references() end, {})
  
  vim.api.nvim_create_user_command('PKMLinkNote', function() require('pkm.notes').link_to_note() end, {})
  vim.api.nvim_create_user_command('PKMFollowLink', function() require('pkm.notes').follow_link() end, {})
  vim.api.nvim_create_user_command('PKMBacklinks', function() require('pkm.notes').show_backlinks() end, {})

  vim.api.nvim_create_user_command('PKMStats', function()
      require('pkm.ui').show_stats()
  end, { desc = "Show PKM statistics" })
end
