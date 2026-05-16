-- =============================================================================
-- pkm.commands — User command registration
-- =============================================================================
-- Dependencies : none (all modules required lazily inside handlers)
-- Consumed by  : pkm.init (called once during setup)
--
-- All handlers use lazy require so no module is loaded until its command
-- is first invoked. Handlers that call init.lua functions must use
-- require('pkm') rather than a local M reference.
--
-- Public API:
--   register() → Register all :PKM* commands with Neovim
-- =============================================================================

local M = {}

-- =============================================================================
-- SECTION: Registration
-- =============================================================================
--- Register all :PKM* user commands. Called once by init.lua during setup.
--- Safe to call again (nvim_create_user_command overwrites existing commands).
function M.register()
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
    require('pkm').delete_note_safely() 
  end, {})

  vim.api.nvim_create_user_command('PKMImport', function() 
      require('pkm.notes').import_note() 
  end, { desc = "Import current file into PKM system" })
   
  vim.api.nvim_create_user_command('PKMToggleAutoSync', function()
    local pkm = require('pkm')

    pkm.config.sync.auto_sync_on_save = not pkm.config.sync.auto_sync_on_save
    local status = pkm.config.sync.auto_sync_on_save and "enabled" or "disabled"
    vim.notify("Auto-sync on save: " .. status, vim.log.levels.INFO)
    vim.api.nvim_clear_autocmds({ group = "PKMSync" })
    if pkm.config.sync.enabled then pkm.setup_sync_autocmds() end
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

  vim.api.nvim_create_user_command('PKMTranspose', function()
    require('pkm.notes').transpose_note()
  end, { desc = "Move note to a different PKM folder and convert it" })

  vim.api.nvim_create_user_command('PKMChangeType', function()
    require('pkm.notes').change_note_type()
  end, { desc = "Change the type of a consolidated note (note/agg/bib)" })

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

  vim.api.nvim_create_user_command('PKMView', function(opts)
    require('pkm.views').open(opts.args ~= '' and opts.args or nil)
  end, {
    nargs = '?',
    complete = function()
      return require('pkm.views').list()
    end,
    desc = 'Open a named project view (tab-completes view names)',
  })

  vim.api.nvim_create_user_command('PKMViews', function()
    local names = require('pkm.views').list()
    if #names == 0 then
      vim.notify('PKMView: no views defined in config.projects', vim.log.levels.INFO)
      return
    end
    vim.notify('Defined views: ' .. table.concat(names, ', '), vim.log.levels.INFO)
  end, { desc = 'List all defined project views' })
end

return M
