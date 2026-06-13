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

  -- ---------------------------------------------------------------------------
  -- Note creation
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMNewNote', function(opts)
    require('pkm.notes').create_new_note(opts.args ~= '' and opts.args or nil)
  end, { nargs = '?' })

  vim.api.nvim_create_user_command('PKMNewJournal', function()
    require('pkm.journal').create_entry(true)
  end, {})

  vim.api.nvim_create_user_command('PKMNewScratchpad', function()
    require('pkm.notes').create_scratchpad()
  end, {})

  -- ---------------------------------------------------------------------------
  -- Note file operations
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMDeleteNote', function()
    require('pkm').delete_note_safely()
  end, {})

  vim.api.nvim_create_user_command('PKMImport', function()
    require('pkm.notes').import_note()
  end, { desc = 'Import current file into PKM system' })

  vim.api.nvim_create_user_command('PKMRenameNote', function()
    require('pkm.notes').rename_note()
  end, { desc = 'Rename current consolidated note file' })

  -- ---------------------------------------------------------------------------
  -- Note conversion and promotion
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMConvertNote', function()
    require('pkm.notes').convert_note()
  end, { desc = 'Convert current note to a different type' })

  vim.api.nvim_create_user_command('PKMPromote', function()
    require('pkm.notes').promote_note()
  end, { desc = 'Promote scratchpad to consolidated note or journal' })

  vim.api.nvim_create_user_command('PKMTranspose', function()
    require('pkm.notes').transpose_note()
  end, { desc = 'Move note to a different PKM folder and convert it' })

  vim.api.nvim_create_user_command('PKMChangeType', function()
    require('pkm.notes').change_note_type()
  end, { desc = 'Change the type of a consolidated note (note/agg/bib)' })

  -- ---------------------------------------------------------------------------
  -- Sync control
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMToggleAutoSync', function()
    local pkm = require('pkm')
    pkm.config.sync.auto_sync_on_save = not pkm.config.sync.auto_sync_on_save
    local status = pkm.config.sync.auto_sync_on_save and 'enabled' or 'disabled'
    vim.notify('Auto-sync on save: ' .. status, vim.log.levels.INFO)
    vim.api.nvim_clear_autocmds({ group = 'PKMSync' })
    if pkm.config.sync.enabled then pkm.setup_sync_autocmds() end
  end, { desc = 'Toggle automatic reference synchronization' })

  -- ---------------------------------------------------------------------------
  -- Search and browse
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMBrowse', function(opts)
    local expr = opts.args ~= '' and opts.args or nil
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').browse(expr)
    else
      require('pkm.ui').browse(expr)
    end
  end, {
    nargs = '*',      
    desc  = 'Browse PKM notes with optional filter expression (tag:x AND title:y etc.)',
  })

  vim.api.nvim_create_user_command('PKMTags', function()
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').browse_tags()
    else
      require('pkm.ui').browse_tags()
    end
  end, { desc = 'Browse notes by tag (Telescope picker or ui fallback)' })

  vim.api.nvim_create_user_command('PKMMergeTags', function()
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').merge_tags_picker()
    else
      require('pkm.ui').merge_tags_ui()
    end
  end, { desc = 'Merge tags across all notes' })

  -- ---------------------------------------------------------------------------
  -- Citations
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMInsertCitation', function()
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').insert_citation_picker()
    else
      require('pkm.ui').insert_citation_ui()
    end
  end, { desc = 'Insert a citation at cursor (Telescope picker or ui fallback)' })

  vim.api.nvim_create_user_command('PKMGotoCitation', function()
    require('pkm.citations').goto_citation()
  end, {})

  vim.api.nvim_create_user_command('PKMUpdateReferences', function()
    require('pkm.citations').update_references()
  end, {})

  -- ---------------------------------------------------------------------------
  -- Navigation and linking
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMLinkNote', function()
    require('pkm.notes').link_to_note()
  end, {})

  vim.api.nvim_create_user_command('PKMFollowLink', function()
    require('pkm.notes').follow_link()
  end, {})

  vim.api.nvim_create_user_command('PKMBacklinks', function()
    require('pkm.notes').show_backlinks()
  end, {})

  -- ---------------------------------------------------------------------------
  -- Stats
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMStats', function()
    require('pkm.ui').show_stats()
  end, { desc = 'Show PKM statistics' })

  -- ---------------------------------------------------------------------------
  -- Views
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMView', function(opts)
    require('pkm.views').open(opts.args ~= '' and opts.args or nil)
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Open a named project view (tab-completes view names)',
  })

  vim.api.nvim_create_user_command('PKMViews', function()
    require('pkm.views').list_views()
  end, { desc = 'Browse all defined views in a tree picker' })

  vim.api.nvim_create_user_command('PKMViewNew', function()
    local views = require('pkm.views')

    vim.ui.select({ 'Simple view', 'Subproject' }, {
      prompt = 'View type:',
    }, function(choice)
      if not choice then return end

      vim.ui.input({ prompt = 'View name: ' }, function(name)
        if not name or name:match('^%s*$') then return end
        name = name:match('^%s*(.-)%s*$')

        -- Detect existing view and offer to edit it
        if vim.tbl_contains(views.list(), name) then
          vim.fn.inputsave()
          local answer = vim.fn.input(
            string.format("View '%s' already exists. Edit it? (y/n): ", name))
          vim.fn.inputrestore()
          if answer:lower() == 'y' then
            vim.schedule(function() views.edit_view(name) end)
          else
            vim.notify('[pkm] cancelled', vim.log.levels.INFO)
          end
          return
        end

        if choice == 'Simple view' then
          vim.ui.input({ prompt = 'Filter expression: ' }, function(expr)
            if not expr or expr:match('^%s*$') then return end
            views.save(name, (expr:match('^%s*(.-)%s*$')))
          end)

        else
          local names = views.list()
          if #names == 0 then
            vim.notify(
              '[pkm] no views defined. Create a simple view first.',
              vim.log.levels.WARN)
            return
          end

          vim.ui.select(names, {
            prompt      = 'Select parent view:',
            format_item = function(n) return n end,
          }, function(parent)
            if not parent then return end

            vim.ui.input({
              prompt = string.format(
                "Filter for '%s' (added to '%s'): ", name, parent),
            }, function(expr)
              if not expr or expr:match('^%s*$') then return end
              expr = expr:match('^%s*(.-)%s*$')

              vim.fn.inputsave()
              local answer = vim.fn.input(string.format(
                "Create subproject '%s' under '%s'"
                  .. " with filter '%s'? (yes/no): ",
                name, parent, expr))
              vim.fn.inputrestore()

              if answer:lower() ~= 'yes' then
                vim.notify('[pkm] subproject creation cancelled',
                  vim.log.levels.INFO)
                return
              end

              views.save_subproject(name, parent, expr)
            end)
          end)
        end
      end)
    end)
  end, {
    desc = 'Create a new view; prompts to edit if the name already exists',
  })

  vim.api.nvim_create_user_command('PKMViewUpdate', function(opts)
    local name = opts.args ~= '' and opts.args or nil
    require('pkm.views').edit_view(name)
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Edit an existing view (expression pre-filled; <C-r> to reset)',
  })

  vim.api.nvim_create_user_command('PKMViewEdit', function()
    local path = require('pkm.utils').join(require('pkm').config.root_path, 'views.json')
    if vim.fn.filereadable(path) == 0 then
      vim.fn.writefile({ '{}' }, path)
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
  end, { desc = 'Open views.json for direct editing' })

  vim.api.nvim_create_user_command('PKMViewDelete', function(opts)
    local name = opts.args ~= '' and opts.args or nil
    if not name then
      local views = require('pkm.views')
      vim.ui.select(views.list(), { prompt = 'Delete view:' }, function(sel)
        if sel then views.delete(sel) end
      end)
      return
    end
    require('pkm.views').delete(name)
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Delete a named project view from views.json',
  })

  vim.api.nvim_create_user_command('PKMViewLast', function()
    require('pkm.views').open_last()
  end, { desc = 'Reopen the last activated view (session-scoped)' })

  vim.api.nvim_create_user_command('PKMExportView', function(opts)
    local views = require('pkm.views')
    local name  = opts.args ~= '' and opts.args or nil
    if not name then
      vim.ui.select(views.list(), { prompt = 'Export view:' }, function(sel)
        if sel then
          require('pkm.export').export_direct(sel, views.match_all(sel))
        end
      end)
      return
    end
    require('pkm.export').export_direct(name, views.match_all(name))
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Export all notes in a named view',
  })

  vim.api.nvim_create_user_command('PKMViewSidebar', function(opts)
    require('pkm.views').open_sidebar(opts.args ~= '' and opts.args or nil)
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Open or toggle the persistent view sidebar',
  })

  -- ---------------------------------------------------------------------------
  -- Buffer panel
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMBuffers', function()
    require('pkm.ui').toggle_bufpanel()
  end, { desc = 'Toggle the persistent bottom buffer-list panel' })

  -- ---------------------------------------------------------------------------
  -- Exporting
  -- ---------------------------------------------------------------------------

  vim.api.nvim_create_user_command('PKMExport', function()
    require('pkm.export').interactive_export()
  end, { desc = 'Open the export filter form (filter notes and copy to a folder)' })

-- =============================================================================
-- SECTION: Markdown editing
-- =============================================================================
  vim.api.nvim_create_user_command('PKMNextHeader', function()
    require('pkm.markdown').append_next_header()
  end, { desc = 'Duplicate current header with counter incremented, append at EOF' })

  vim.api.nvim_create_user_command('PKMHeaderLevelUp', function(opts)
    require('pkm.markdown').shift_header_level('up', opts.line1, opts.line2)
  end, { range = '%', desc = 'Increase header level in range (default: whole buffer)' })

  vim.api.nvim_create_user_command('PKMHeaderLevelDown', function(opts)
    require('pkm.markdown').shift_header_level('down', opts.line1, opts.line2)
  end, { range = '%', desc = 'Decrease header level in range (default: whole buffer)' })

  vim.api.nvim_create_user_command('PKMRenumberList', function(opts)
    local md = require('pkm.markdown')
    if opts.range > 0 then
      md.renumber_sequence(opts.line1, opts.line2)
    else
      md.renumber_at_cursor()
    end
  end, { range = true, desc = 'Renumber ordered sequence in range or current paragraph' })

end

return M
