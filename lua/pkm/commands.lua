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
-- SECTION: Helpers
-- =============================================================================

--- Command-line completion for :PKMBrowse filter expressions.
--- Suggests field prefixes, boolean operators, and 'tag:<value>' completions
--- sourced from the index (if already built).
---@param arg_lead string   Current word being completed
---@return string[]
local function browse_complete(arg_lead, _cmd_line, _cursor_pos)
  local keywords = {
  'AND', 'OR', 'NOT',
  'tag:', 'title:', 'text:', 'filename:', 'any:', 'type:',
  }

  -- After 'tag:' prefix: suggest 'tag:<known-tag>' candidates.
  local tag_stub = arg_lead:match('^tag:(.*)$')
  if tag_stub ~= nil then
    local index = require('pkm.index')
    if not index.is_built() then return {} end
    local seen, out = {}, {}
    local stub_lower = tag_stub:lower()
    for _, e in ipairs(index.get_all()) do
      for _, t in ipairs(e.tags or {}) do
        if not seen[t] and t:find(stub_lower, 1, true) then
          seen[t] = true
          out[#out + 1] = 'tag:' .. t
        end
      end
    end
    table.sort(out)
    return out
  end

  local type_stub = arg_lead:match('^type:(.*)$')
  if type_stub ~= nil then
    local types = { 'note', 'agg', 'bib', 'journal', 'scratch', 'other' }
    local out = {}
    for _, t in ipairs(types) do
      if t:find(type_stub, 1, true) then out[#out + 1] = 'type:' .. t end
    end
    return out
  end

  -- General: filter all static tokens by the current arg_lead.
  local lead_lower = arg_lead:lower()
  local out = {}
  for _, tok in ipairs(keywords) do
    if tok:lower():find(lead_lower, 1, true) then
      out[#out + 1] = tok
    end
  end
  return out
end

--- If the current window is a PKM panel (sidebar, bufpanel) or netrw,
--- switch focus to the nearest non-panel, non-float main editing window.
--- Falls back to opening a new split. Ensures creation commands never
--- open note buffers inside the sidebar, buffer panel, or file explorer.
local function focus_main_win()
  local ft = vim.bo.filetype
  if ft ~= 'pkm-sidebar' and ft ~= 'pkm-bufpanel' and ft ~= 'netrw' then return end

  local cur = vim.api.nvim_get_current_win()
  local _PANELS = { ['pkm-sidebar'] = true, ['pkm-bufpanel'] = true, ['netrw'] = true }

  -- Prefer the alternate window if it is a main editing window.
  local alt = vim.fn.win_getid(vim.fn.winnr('#'))
  if alt ~= 0 and alt ~= cur
  and vim.api.nvim_win_is_valid(alt)
  and vim.api.nvim_win_get_config(alt).relative == '' then
    local alt_ft = vim.bo[vim.api.nvim_win_get_buf(alt)].filetype
    if not _PANELS[alt_ft] then
      vim.api.nvim_set_current_win(alt)
      return
    end
  end

  -- Fall back to the first non-panel, non-float window.
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= cur and vim.api.nvim_win_get_config(win).relative == '' then
      local win_ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
      if not _PANELS[win_ft] then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end

  -- No suitable window exists; create one.
  vim.cmd('noautocmd rightbelow vsplit')
end

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
    focus_main_win()
    require('pkm.notes').create_new_note(opts.args ~= '' and opts.args or nil)
  end, { nargs = '?' })

  vim.api.nvim_create_user_command('PKMNewJournal', function()
    focus_main_win()
    require('pkm.journal').create_entry(true)
  end, {})

  vim.api.nvim_create_user_command('PKMNewScratchpad', function()
    focus_main_win()
    require('pkm.notes').create_scratchpad()
  end, {})

  -- ---------------------------------------------------------------------------
  -- Note file operations
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMDeleteNote', function()
    require('pkm').delete_note_safely()
  end, {})

  vim.api.nvim_create_user_command('PKMImport', function()
    focus_main_win()
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
    focus_main_win()
    local expr = opts.args ~= '' and opts.args or nil
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').browse(expr)
    else
      require('pkm.ui').browse(expr)
    end
  end, {
    nargs    = '*',
    complete = browse_complete,
    desc     = 'Browse PKM notes with optional filter expression (tag:x AND title:y etc.)',
  })

  vim.api.nvim_create_user_command('PKMTags', function()
    focus_main_win()
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

  vim.api.nvim_create_user_command('PKMBrowseRecent', function(opts)
    focus_main_win()
    local n = tonumber(opts.args) or 20
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').browse_recent(n)
    else
      require('pkm.ui').browse_recent(n)
    end
  end, {
    nargs = '?',
    desc  = 'Show the n most recently modified notes (default 20)',
  })

  vim.api.nvim_create_user_command('PKMOrphans', function()
    focus_main_win()
    local index = require('pkm.index')
    local views = require('pkm.views')
    local utils = require('pkm.utils')

    -- Build a set of paths that appear in at least one defined view.
    local viewed = {}
    for _, vname in ipairs(views.list()) do
      for _, path in ipairs(views.match_all(vname)) do
        viewed[utils.normalize(path)] = true
      end
    end

    -- An orphan has no tags, no citations, and belongs to no view.
    local orphan_paths = {}
    for _, e in ipairs(index.get_all()) do
      if (not e.has_citations)
      and (#(e.tags or {}) == 0)
      and (not viewed[utils.normalize(e.path)]) then
        orphan_paths[#orphan_paths + 1] = e.path
      end
    end

    if #orphan_paths == 0 then
      vim.notify('[pkm] no orphaned notes', vim.log.levels.INFO)
      return
    end

    local label    = string.format('Orphans (%d)', #orphan_paths)
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').browse_paths(label, orphan_paths)
    else
      require('pkm.ui').browse_paths(label, orphan_paths)
    end
  end, { desc = 'Show notes with no tags, no citations, and no matching view' })

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
  -- Frontmatter editing (buffer-only; no disk write; no index.invalidate)
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMSetTitle', function()
    require('pkm.notes').set_title()
  end, { desc = 'Set title frontmatter field in current buffer (no disk write)' })

  vim.api.nvim_create_user_command('PKMAddTag', function(opts)
    if opts.args ~= '' then
      require('pkm.citations').add_tag(opts.args)
    else
      require('pkm.ui').open_tag_panel('add')
    end
  end, { nargs = '?', desc = 'Append a tag via the tag panel, or directly if an argument is given (no disk write)' })

  vim.api.nvim_create_user_command('PKMRemoveTag', function(opts)
    if opts.args ~= '' then
      require('pkm.citations').remove_tag(opts.args)
    else
      require('pkm.ui').open_tag_panel('remove')
    end
  end, { nargs = '?', desc = 'Remove a tag via the tag panel, or directly if an argument is given (no disk write)' })

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
    focus_main_win()
    require('pkm.views').open(opts.args ~= '' and opts.args or nil)
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Open a named project view (tab-completes view names)',
  })

  vim.api.nvim_create_user_command('PKMViews', function()
    require('pkm.views').open_views_panel()
  end, { desc = 'Browse all defined views (panel; <Tab> to browse all notes)' })

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
              -- No confirmation gate: creating a view/subview is safe and
              -- trivially reversible (delete it, or :PKMViewUpdate to fix a
              -- wrong parameter) — confirmation stays reserved for actually
              -- dangerous actions (deletion, everywhere else in this file).
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
    focus_main_win()
    local path = require('pkm.utils').join(require('pkm').config.root_path, 'views.json')
    if vim.fn.filereadable(path) == 0 then
      vim.fn.writefile({ '{}' }, path)
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
  end, { desc = 'Open views.json for direct editing' })

  vim.api.nvim_create_user_command('PKMViewDelete', function(opts)
    local name = opts.args ~= '' and opts.args or nil
    if not name then
      require('pkm.views').open_view_deletion_panel()
      return
    end
    -- Direct-argument fast path retains its own confirmation — "deletion
    -- always confirmed" applies here too, not just to the panel.
    local choice = vim.fn.confirm(
      string.format("Delete view '%s'?", name), '&Yes\n&No', 2)
    if choice == 1 then
      require('pkm.views').delete(name)
    end
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Delete a named project view (panel if no argument; confirms either way)',
  })

  vim.api.nvim_create_user_command('PKMViewLast', function()
    focus_main_win()
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

  -- :PKMRestoreNote — open the browse/search/restore panel.
  vim.api.nvim_create_user_command('PKMRestoreNote', function()
    require('pkm.trash').open_restore_panel()
  end, { desc = 'Browse and restore notes from the PKM trash' })

  -- :PKMEmptyTrash — permanently delete all trashed notes and strip backlinks.
  vim.api.nvim_create_user_command('PKMEmptyTrash', function()
    local trash = require('pkm.trash')
    local entries = trash.list()
    if #entries == 0 then
      vim.notify('[pkm] trash is already empty', vim.log.levels.INFO)
      return
    end
    vim.fn.inputsave()
    local confirm = vim.fn.input(string.format(
      'Permanently delete %d trashed note%s and strip backlinks? (yes/no): ',
      #entries, #entries == 1 and '' or 's'))
    vim.fn.inputrestore()
    if confirm:lower() ~= 'yes' then
      vim.notify('[pkm] cancelled', vim.log.levels.INFO)
      return
    end
    local count = trash.empty()
    vim.notify(string.format('[pkm] permanently deleted %d note%s from trash',
      count, count == 1 and '' or 's'), vim.log.levels.INFO)
  end, { desc = 'Permanently delete all PKM trash and strip backlinks' })

  -- :PKMConvertList [to_ordered|to_unordered] — ordered ↔ unordered conversion.
  vim.api.nvim_create_user_command('PKMConvertList', function(opts)
    local md  = require('pkm.markdown')
    local dir = opts.args ~= '' and opts.args or nil
    if dir and dir ~= 'to_ordered' and dir ~= 'to_unordered' then
      vim.notify('[pkm] invalid direction: use to_ordered or to_unordered',
        vim.log.levels.WARN)
      return
    end
    if opts.range > 0 then
      md.convert_list(opts.line1, opts.line2, dir)
    else
      md.convert_list_at_cursor(dir)
    end
  end, {
    range    = true,
    nargs    = '?',
    complete = function() return { 'to_ordered', 'to_unordered' } end,
    desc     = 'Convert list between ordered/unordered; optional direction arg',
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

  -- ---------------------------------------------------------------------------
  -- Toggles
  -- ---------------------------------------------------------------------------
  -- :PKMMode [on|off] — activate, deactivate, or toggle PKM session context.
  vim.api.nvim_create_user_command('PKMMode', function(opts)
    require('pkm.mode').set(opts.args:match('^%s*(.-)%s*$'))
  end, {
    nargs = '?',
    complete = function() return { 'on', 'off' } end,
    desc = 'Toggle PKM mode (explorer + index + syntax)',
  })

  -- :PKMExplorer — toggle sidebar + bufpanel as a unit, independent of mode state.
  -- If both open: close both. If either closed: open both.
  vim.api.nvim_create_user_command('PKMExplorer', function()
    local views = require('pkm.views')
    local ui    = require('pkm.ui')
    local s = views.is_sidebar_open()
    local b = ui.is_bufpanel_open()
    if s and b then
      views.open_sidebar()
      ui.toggle_bufpanel()
    else
      if not s then views.open_sidebar()   end
      if not b then ui.toggle_bufpanel()   end
    end
  end, { desc = 'Toggle PKM explorer (sidebar + buffer panel)' })

  -- ---------------------------------------------------------------------------
  -- Markdown editing
  -- ---------------------------------------------------------------------------
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
