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

--- If the current window is a PKM panel (sidebar, bufpanel) or netrw, switch
--- focus to a real editing window, creating one if the tabpage has none.
--- Ensures commands never open note buffers inside a panel.
---
--- The search itself lives in `pkm.utils` — it was duplicated here and in
--- `views`, and note creation needed a third copy, which is one copy too many.
---@param where nil|'left'|'right'|integer  Passed through to utils
local function focus_main_win(where)
  require('pkm.utils').focus_editing_win(where)
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
  -- :PKMNewNote [note|agg|bib] [left|right|N] — the placement is an argument
  -- rather than a second command. Both are optional and order-free: the type
  -- comes from a closed set and the placement is a side or a window number, so
  -- neither can be mistaken for the other.
  vim.api.nvim_create_user_command('PKMNewNote', function(opts)
    local note_type, where
    for _, arg in ipairs(opts.fargs) do
      local low = arg:lower()
      if low == 'note' or low == 'agg' or low == 'bib' then
        note_type = low
      elseif low == 'left' or low == 'right' then
        where = low
      elseif low:match('^%d+$') then
        where = tonumber(low)
      else
        vim.notify(string.format("[pkm] don't know what '%s' means here — "
          .. 'expected a type (note/agg/bib) or a place (left/right/<number>)',
          arg), vim.log.levels.ERROR)
        return
      end
    end

    require('pkm.notes').create_new_note(note_type, { where = where })
  end, {
    nargs    = '*',
    complete = function(lead)
      local out = {}
      for _, tok in ipairs({ 'note', 'agg', 'bib', 'left', 'right' }) do
        if tok:find(lead:lower(), 1, true) == 1 then out[#out + 1] = tok end
      end
      return out
    end,
    desc = 'Create a note; optional type and placement (left/right/window number)',
  })

  -- :PKMNewRelative — new note seeded with the current note's tags, so it lands
  -- in the same views without retyping its classification.
  vim.api.nvim_create_user_command('PKMNewRelative', function(opts)
    require('pkm.notes').create_relative_note(opts.args ~= '' and opts.args or nil)
  end, {
    nargs    = '?',
    complete = function() return { 'note', 'agg', 'bib' } end,
    desc     = "Create a note inheriting the current note's tags",
  })

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

  -- :PKMTags — the tag browser, or one batch operation stated in arguments.
  -- Bare, it goes straight to the browser: the mode menu was a screen that
  -- decided nothing for the common case. Batch operations belong to the
  -- navigation panels, where the notes are chosen (<C-a>); the argument form is
  -- the deterministic path for scripts and advanced users, and always ends at
  -- the change list. Without Telescope the old mode menu is the fallback.
  vim.api.nvim_create_user_command('PKMTags', function(opts)
    focus_main_win()
    local tags = require('pkm.tags')

    if #opts.fargs > 0 then
      local mode, ops, header, err = tags.parse_command_args(opts.fargs)
      if err then
        vim.notify('[pkm] :PKMTags — ' .. err, vim.log.levels.ERROR)
        return
      end
      if mode == 'browse' then
        tags.browse_by_tag()
      elseif ops then
        -- Stated in full, so the scope is the whole vault; the change list is
        -- still shown, and nothing is written until it is confirmed.
        tags.batch_on(tags.all_note_paths(), mode, ops, header)
      else
        tags.batch_flow(mode)
      end
      return
    end

    if pcall(require, 'telescope') then
      tags.browse_by_tag()
      return
    end

    vim.ui.select({
      'Browse by tag',
      'Add a tag to notes…',
      'Remove a tag from notes…',
      'Rename a tag on notes…',
    }, { prompt = 'Tags:' }, function(_, idx)
      if idx == 1 then tags.browse_by_tag()
      elseif idx == 2 then tags.batch_flow('add')
      elseif idx == 3 then tags.batch_flow('remove')
      elseif idx == 4 then tags.batch_flow('rename')
      end
    end)
  end, {
    nargs    = '*',
    complete = function(arg_lead, cmd_line)
      local words = vim.split(vim.trim(cmd_line), '%s+')
      -- Word 1 is the command itself; the mode is word 2.
      local typing_mode = #words < 2 or (#words == 2 and arg_lead ~= '')

      local candidates = {}
      if typing_mode then
        candidates = { 'browse', 'add', 'remove', 'rename' }
      elseif words[2] == 'remove' or words[2] == 'rename' then
        for _, row in ipairs(require('pkm.tags').tag_counts()) do
          candidates[#candidates + 1] = row.tag
        end
      end

      return vim.tbl_filter(function(c)
        return c:find(arg_lead, 1, true) == 1
      end, candidates)
    end,
    desc = 'Browse notes by tag; with arguments, run one batch tag operation',
  })

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

    -- The set of paths that appear in at least one defined view. match_set
    -- reads the index once for the whole batch; the match_all loop this
    -- replaces read it once per view and sorted each result by basename, an
    -- order a membership test cannot use.
    local viewed = views.match_set(views.list())

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
  -- :PKMView [add|remove] [name] — open a view, or move the current note in or
  -- out of one. No second command: the verbs are arguments, and a bare name
  -- still means "open", so nothing that worked before reads differently now.
  vim.api.nvim_create_user_command('PKMView', function(opts)
    local views = require('pkm.views')
    local mode, name, err = views.parse_command_args(opts.fargs, views.list())

    if err then
      vim.notify('[pkm] ' .. err, vim.log.levels.ERROR)
      return
    end

    if mode == 'open' then
      focus_main_win()
      views.open(name)
      return
    end

    -- The note under the cursor is the whole selection here.
    local filepath = vim.fn.expand('%:p')
    local root     = require('pkm').config.root_path or ''
    local in_root  = filepath ~= '' and root ~= ''
      and filepath:gsub('\\', '/'):lower():find(root:gsub('\\', '/'):lower(), 1, true)
    if not in_root or not filepath:match('%.md$') then
      vim.notify('[pkm] not a PKM note — open one first', vim.log.levels.WARN)
      return
    end

    require('pkm.tags').view_flow({ filepath }, mode, { target = name })
  end, {
    nargs    = '*',
    complete = function(_, line)
      local views = require('pkm.views')
      -- After a verb, only view names make sense; before it, both do.
      if line:match('^%s*PKMView%s+[Aa][Dd][Dd]%s')
      or line:match('^%s*PKMView%s+[Rr][Ee][Mm][Oo][Vv][Ee]%s') then
        return views.list()
      end
      local out = { 'add', 'remove' }
      vim.list_extend(out, views.list())
      return out
    end,
    desc     = 'Open a view, or add/remove the current note (:PKMView add <name>)',
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

  -- :PKMExport — simple (filter only) or deep (filter, then walk the citation
  -- graph out from the matches). Native vim.ui.select: the choice set is small
  -- and fixed, so it does not warrant a panel of its own.
  vim.api.nvim_create_user_command('PKMExport', function()
    local export = require('pkm.export')
    vim.ui.select(
      { 'Simple — export the notes you select',
        'Deep   — also export what those notes cite and what cites them' },
      { prompt = 'Export mode:' },
      function(_, idx)
        if idx == 1 then
          export.interactive_export()
        elseif idx == 2 then
          export.deep_export()
        end
      end)
  end, { desc = 'Export notes: filter form, optionally expanded across citations' })

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
  -- Renamed from :PKMNextHeader in v1.10.0. It edits the buffer, while
  -- :PKMHeaderNext only moves the cursor; under the old pair of names the
  -- wrong one was a completion away, and the wrong one writes. The keymap
  -- config key stays `next_header` so existing setups keep working.
  vim.api.nvim_create_user_command('PKMHeaderAppend', function()
    require('pkm.markdown').append_next_header()
  end, { desc = 'Duplicate current header with counter incremented, append at EOF' })

  -- :PKMHeaderNext / :PKMHeaderPrev [same|h1-h6], with an optional count —
  -- :3PKMHeaderNext. Complements Neovim's native ]] / [[ (see markdown.lua
  -- § Header navigation for what those already cover).
  --
  -- The level is `h2`, not `2`, because these commands take a count, and Vim
  -- reads a leading number in the arguments AS the count: `:PKMHeaderNext 6`
  -- means six headers ahead, and always did. Spelling the level `h6` leaves
  -- one reading per form instead of two for the same words.
  local function header_motion(dir)
    return function(opts)
      local level = nil
      if opts.args ~= '' then
        level = (opts.args == 'same') and 'same' or tonumber(opts.args:match('^[hH]([1-6])$'))
        if level == nil then
          vim.notify(
            '[pkm] use same or h1-h6 for the level; a bare number is the count',
            vim.log.levels.WARN)
          return
        end
      end
      require('pkm.markdown').goto_heading({
        dir   = dir,
        count = opts.count > 0 and opts.count or 1,
        level = level,
      })
    end
  end

  local header_levels = { 'same', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6' }

  vim.api.nvim_create_user_command('PKMHeaderNext', header_motion('next'), {
    count    = true,
    nargs    = '?',
    complete = function() return header_levels end,
    desc     = 'Jump to the next header (any level; arg restricts it)',
  })

  vim.api.nvim_create_user_command('PKMHeaderPrev', header_motion('prev'), {
    count    = true,
    nargs    = '?',
    complete = function() return header_levels end,
    desc     = 'Jump to the previous header (any level; arg restricts it)',
  })

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
