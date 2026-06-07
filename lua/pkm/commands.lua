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
  vim.api.nvim_create_user_command('PKMSearch', function()
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').search_notes()
    else
      require('pkm.ui').search_notes()
    end
  end, { desc = 'Raw text search via ripgrep (Telescope live_grep)' })

  vim.api.nvim_create_user_command('PKMBrowse', function(opts)
    local expr = opts.args ~= '' and opts.args or nil
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').browse(expr)
    else
      require('pkm.ui').browse(expr)
    end
  end, {
    nargs = '?',
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
    vim.ui.input({ prompt = 'View name: ' }, function(name)
      if not name or name:match('^%s*$') then return end
      vim.ui.input({ prompt = 'Filter expression: ' }, function(expr)
        if not expr or expr:match('^%s*$') then return end
        require('pkm.views').save(name, expr)
      end)
    end)
  end, { desc = 'Create or update a named project view' })

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

  vim.api.nvim_create_user_command('PKMViewSidebar', function(opts)
    require('pkm.views').open_sidebar(opts.args ~= '' and opts.args or nil)
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Open or toggle the persistent view sidebar',
  })

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

  vim.api.nvim_create_user_command('PKMHeadingNext', function()
    require('pkm.markdown').goto_heading('next')
  end, { desc = 'Jump to next Markdown heading' })

  vim.api.nvim_create_user_command('PKMHeadingPrev', function()
    require('pkm.markdown').goto_heading('prev')
  end, { desc = 'Jump to previous Markdown heading' })

end

return M
