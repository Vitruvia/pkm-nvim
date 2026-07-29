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
  -- `title=` is the one named value: a title that comes with it skips the
  -- prompt, so `:PKMNewNote note title=Foo` creates without interaction. It is a
  -- single token, because Neovim splits arguments on whitespace before the
  -- callback sees them; a spaced title is set afterwards with :PKMSetTitle, or
  -- through the prompt.
  vim.api.nvim_create_user_command('PKMNewNote', function(opts)
    local p = require('pkm.args').parse(opts, { named = true })
    local note_type, where
    for _, arg in ipairs(p.positional) do
      local low = arg:lower()
      if low == 'note' or low == 'agg' or low == 'bib' then
        note_type = low
      elseif low == 'left' or low == 'right' then
        where = low
      elseif low:match('^%d+$') then
        where = tonumber(low)
      else
        vim.notify(string.format("[pkm] don't know what '%s' means here — "
          .. 'expected a type (note/agg/bib), a place (left/right/<number>) '
          .. 'or title=<text>', arg), vim.log.levels.ERROR)
        return
      end
    end

    require('pkm.notes').create_new_note(note_type, { where = where, title = p.named.title })
  end, {
    nargs    = '*',
    complete = function(lead)
      local out = {}
      for _, tok in ipairs({ 'note', 'agg', 'bib', 'left', 'right', 'title=' }) do
        if tok:find(lead:lower(), 1, true) == 1 then out[#out + 1] = tok end
      end
      return out
    end,
    desc = 'Create a note; optional type, placement (left/right/N) and title=<text>',
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

  -- The whole argument string is the new name, so a spaced name needs no
  -- quoting; with no argument it prompts. The number and type prefix of a
  -- consolidated note are kept either way.
  vim.api.nvim_create_user_command('PKMRenameNote', function(opts)
    require('pkm.notes').rename_note(opts.args ~= '' and opts.args or nil)
  end, {
    nargs = '*',
    desc  = 'Rename the current note (argument = new name; prompts if none)',
  })

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

  -- The current note is the source; the argument names the target. With no
  -- argument, :PKMCite falls back to the interactive picker (the same one
  -- :PKMInsertCitation opens), keeping the two forms one command. The target
  -- is a note path, an identifier (note-0042) or a token (note[0042]).
  local function current_note()
    local path = vim.fn.expand('%:p')
    local root = require('pkm').config.root_path or ''
    local in_root = path ~= '' and root ~= ''
      and path:gsub('\\', '/'):lower():find(root:gsub('\\', '/'):lower(), 1, true)
    if not in_root or not path:match('%.md$') then
      vim.notify('[pkm] not a PKM note — open one first', vim.log.levels.WARN)
      return nil
    end
    return path
  end

  vim.api.nvim_create_user_command('PKMCite', function(opts)
    local citations = require('pkm.citations')
    if opts.args == '' then
      if pcall(require, 'telescope') then
        require('pkm.telescope').insert_citation_picker()
      else
        require('pkm.ui').insert_citation_ui()
      end
      return
    end
    local source = current_note()
    if not source then return end
    local ok, err = citations.cite(source, opts.args)
    if ok then
      vim.notify('[pkm] cited ' .. opts.args, vim.log.levels.INFO)
    else
      vim.notify('[pkm] ' .. (err or 'not cited'), vim.log.levels.ERROR)
    end
  end, {
    nargs = '?',
    desc  = 'Cite a note from the current one (picker if no argument)',
  })

  vim.api.nvim_create_user_command('PKMUncite', function(opts)
    local citations = require('pkm.citations')
    local source = current_note()
    if not source then return end

    local function remove(ref)
      local ok, n, err = citations.uncite(source, ref)
      if ok then
        vim.notify(string.format('[pkm] removed %d citation%s of %s',
          n, n == 1 and '' or 's', ref), vim.log.levels.INFO)
      else
        vim.notify('[pkm] ' .. (err or 'not removed'), vim.log.levels.ERROR)
      end
    end

    if opts.args ~= '' then
      remove(opts.args)
      return
    end

    -- No argument: choose from what this note currently cites.
    local fm = require('pkm.yaml').parse_frontmatter(vim.fn.readfile(source))
    local rows = {}
    for _, group in ipairs({ 'notes', 'bib', 'journal', 'scratch' }) do
      for _, e in ipairs((fm and fm.cites and fm.cites[group]) or {}) do
        rows[#rows + 1] = { identifier = e.identifier, title = e.title }
      end
    end
    if #rows == 0 then
      vim.notify('[pkm] this note cites nothing', vim.log.levels.INFO)
      return
    end
    require('pkm.picker').choose(rows, {
      title   = 'Uncite from this note',
      display = function(r) return string.format('%s  %s', r.identifier, r.title or '') end,
    }, function(r) remove(r.identifier) end)
  end, {
    nargs = '?',
    desc  = 'Remove a citation from the current note (picker if no argument)',
  })

  vim.api.nvim_create_user_command('PKMUpdateReferences', function()
    require('pkm.citations').update_references()
  end, {})

  -- ---------------------------------------------------------------------------
  -- Frontmatter editing (buffer-only; no disk write; no index.invalidate)
  -- ---------------------------------------------------------------------------
  -- The whole argument string is the title, so a spaced title needs no quoting;
  -- with no argument it prompts, seeded with the current title.
  vim.api.nvim_create_user_command('PKMSetTitle', function(opts)
    require('pkm.notes').set_title(opts.args ~= '' and opts.args or nil)
  end, {
    nargs = '*',
    desc  = 'Set the title frontmatter field (argument = title; prompts if none; no disk write)',
  })

  -- Buffer-only by default (no disk write), exactly as before. With note=<ref>
  -- it instead writes the tag to that named note on disk — the typed form the
  -- agent path needs, since an agent tags notes it is not "in". The tag itself
  -- is the positional words, so a spaced tag needs no quoting.
  local function tag_command(kind)
    return function(opts)
      local p   = require('pkm.args').parse(opts, { named = true })
      local tag = table.concat(p.positional, ' ')

      if p.named.note then
        if tag == '' then
          vim.notify('[pkm] a tag is required with note=', vim.log.levels.WARN)
          return
        end
        local item, rerr = require('pkm.citations').resolve_citable(p.named.note)
        if not item then
          vim.notify('[pkm] ' .. (rerr or 'note not found'), vim.log.levels.ERROR)
          return
        end
        local ops = (kind == 'add') and { add = { tag } } or { remove = { tag } }
        local ok, werr = require('pkm.tags').write_note_tags(item.path, ops)
        if ok then
          vim.notify(string.format("[pkm] %s '%s' on %s",
            kind == 'add' and 'added' or 'removed', tag, p.named.note), vim.log.levels.INFO)
        else
          vim.notify('[pkm] ' .. (werr or 'not written'), vim.log.levels.ERROR)
        end
        return
      end

      -- No note=: the buffer-only path, unchanged.
      if tag ~= '' then
        require('pkm.citations')[kind == 'add' and 'add_tag' or 'remove_tag'](tag)
      else
        require('pkm.ui').open_tag_panel(kind)
      end
    end
  end

  vim.api.nvim_create_user_command('PKMAddTag', tag_command('add'), {
    nargs = '*',
    desc  = 'Append a tag (panel, or directly; note=<ref> writes to a named note)',
  })

  vim.api.nvim_create_user_command('PKMRemoveTag', tag_command('remove'), {
    nargs = '*',
    desc  = 'Remove a tag (panel, or directly; note=<ref> writes to a named note)',
  })

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

    -- note=<ref> is pulled out first, so it never lands in the view name; what
    -- remains is read exactly as before.
    local p        = require('pkm.args').parse(opts, { named = true })
    local note_ref = p.named.note
    local mode, name, err = views.parse_command_args(p.positional, views.list())

    if err then
      vim.notify('[pkm] ' .. err, vim.log.levels.ERROR)
      return
    end

    if mode == 'open' then
      focus_main_win()
      views.open(name)
      return
    end

    -- A named note (note=<ref>): the deterministic, promptless path. It applies
    -- the view's tag condition when there is one unambiguous way, and refuses
    -- when the view can be satisfied several ways — that choice is the
    -- interactive form's to make.
    if note_ref then
      local item, rerr = require('pkm.citations').resolve_citable(note_ref)
      if not item then
        vim.notify('[pkm] ' .. (rerr or 'note not found'), vim.log.levels.ERROR)
        return
      end
      local ok, serr = views.set_membership(item.path, name, mode)
      if ok then
        vim.notify(string.format("[pkm] %s %s '%s'",
          note_ref, mode == 'add' and 'added to' or 'removed from', name), vim.log.levels.INFO)
      else
        vim.notify('[pkm] ' .. (serr or 'not changed'), vim.log.levels.ERROR)
      end
      return
    end

    -- No note=: the note under the cursor is the whole selection, interactively.
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

  -- ===========================================================================
  -- Vaults
  -- ===========================================================================
  -- A vault is a folder; the registry beside the vaults is what gives it a
  -- number and a name, and the folder `NN - Name` is derived from that pair.
  -- So renaming and renumbering *are* moves, and neither touches a note — which
  -- is why none of these commands has anything to say about note contents.
  --
  -- Only unregistering confirms. It is the one operation here that moves a
  -- whole vault out of the set; the rest are reversible by their opposite.

  local function vault_names()
    local names = {}
    for _, v in ipairs(require('pkm.vault').list()) do names[#names + 1] = v.name end
    return names
  end

  --- Report an (ok, err) pair from pkm.vault in one place.
  local function vault_done(ok, err, success_msg)
    if ok then
      vim.notify('[pkm] ' .. success_msg, vim.log.levels.INFO)
    else
      vim.notify('[pkm] ' .. (err or 'the vault was not changed'), vim.log.levels.ERROR)
    end
  end

  --- Folder names :PKMVaultAdopt can take: everything under Unregistered/, and
  --- every folder beside the vaults that no vault claims.
  ---
  --- The second half is how a vault that predates the registry gets into it —
  --- the first `:PKMVaultAdopt "01 - Vitruvia"` on a Note-Vault that has no
  --- vaults.json yet. Offering only Unregistered/ left that path working but
  --- invisible, which for a first use is the same as missing.
  local function adoptable()
    local vault = require('pkm.vault')
    local roots = { vault.unregistered_dir(), vault.vaults_root() }

    local out, seen = {}, {}
    for _, dir in ipairs(roots) do
      for _, path in ipairs(vim.fn.glob(dir .. '/*', false, true)) do
        local leaf = vim.fn.fnamemodify(path, ':t')
        if vim.fn.isdirectory(path) == 1
        and leaf ~= 'Unregistered'
        and not seen[leaf]
        and vault.of(path) == nil then
          seen[leaf]  = true
          out[#out + 1] = leaf
        end
      end
    end
    return out
  end

  vim.api.nvim_create_user_command('PKMVault', function(opts)
    local vault = require('pkm.vault')

    -- `!` also makes it the vault that opens next time. A bang rather than a
    -- command of its own: "go there, and stay there" is one decision, taken
    -- where the switch is already being made, and the registry is where the
    -- answer has to live — a name in init.lua cannot survive a rename, because
    -- a rename never reads init.lua.
    local function switch(name)
      local ok, err, entry = vault.select(name)
      if not ok then
        vim.notify('[pkm] ' .. (err or 'the vault was not changed'), vim.log.levels.ERROR)
        return
      end

      local msg = 'active vault: ' .. vault.folder_of(entry)
      if opts.bang then
        local ok_def, err_def = vault.set_default(entry.name)
        msg = ok_def and (msg .. ' — and it is now the default')
                      or (msg .. ' — but the default was not saved: ' .. tostring(err_def))
      end
      vim.notify('[pkm] ' .. msg, vim.log.levels.INFO)
    end

    local name = vim.trim(opts.args)
    if name ~= '' then
      switch(name)
      return
    end

    local entries = vault.list()
    if #entries == 0 then
      vim.notify('[pkm] no vaults are registered — :PKMVaultNew makes one', vim.log.levels.INFO)
      return
    end

    -- Listing and switching are one panel, and the panel answers "which one am
    -- I in?" before it asks "which one do you want?".
    local active  = vault.active()
    local default = vault.default()
    require('pkm.picker').choose(entries, {
      title   = 'Vault · ' .. (vault.indicator() ~= '' and vault.indicator() or 'unregistered root'),
      display = function(row)
        local here = active  and active.number  == row.number
        local dflt = default and default.number == row.number
        -- ● where you are, ★ what opens next time; they are different questions
        -- and a list that answered only the first would invite the wrong one.
        return (here and '●' or ' ') .. (dflt and '★' or ' ') .. ' ' .. vault.folder_of(row)
      end,
    }, function(row) switch(row.name) end)
  end, {
    nargs    = '?',
    bang     = true,
    complete = function() return vault_names() end,
    desc     = 'Switch the active vault (no argument lists them; ! also makes it the default)',
  })

  vim.api.nvim_create_user_command('PKMVaultNew', function(opts)
    local vault = require('pkm.vault')
    local name  = vim.trim(opts.args)

    local function make(n)
      local ok, err = vault.create(n, { git = not opts.bang })
      vault_done(ok, err, string.format('vault %s created',
        ok and vault.folder_of(vault.get(n)) or n))
    end

    if name ~= '' then
      make(name)
      return
    end
    vim.ui.input({ prompt = 'New vault name: ' }, function(input)
      if input and vim.trim(input) ~= '' then make(vim.trim(input)) end
    end)
  end, {
    nargs = '?',
    bang  = true,
    desc  = 'Create a vault: folder, skeleton and registry entry (! for no git repository)',
  })

  vim.api.nvim_create_user_command('PKMVaultRename', function(opts)
    local from, to = opts.fargs[1], opts.fargs[2]
    if not from or not to then
      vim.notify('[pkm] :PKMVaultRename <from> <to>', vim.log.levels.WARN)
      return
    end
    local ok, err = require('pkm.vault').rename(from, to)
    vault_done(ok, err, string.format('%s is now named %s', from, to))
  end, {
    nargs    = '+',
    complete = function(_, line)
      -- Only the first argument is a vault: the second is the new name, and
      -- completing an existing vault there would offer exactly the collision
      -- the rename refuses.
      return #vim.split(vim.trim(line), '%s+') > 2 and {} or vault_names()
    end,
    desc = 'Rename a vault, keeping its number (the folder moves; no note changes)',
  })

  vim.api.nvim_create_user_command('PKMVaultRenumber', function(opts)
    local name, n = opts.fargs[1], tonumber(opts.fargs[2])
    if not name or not n then
      vim.notify('[pkm] :PKMVaultRenumber <name> <number>', vim.log.levels.WARN)
      return
    end
    local ok, err = require('pkm.vault').renumber(name, n)
    vault_done(ok, err, string.format('%s is now vault %02d', name, n))
  end, {
    nargs    = '+',
    complete = function(_, line)
      return #vim.split(vim.trim(line), '%s+') > 2 and {} or vault_names()
    end,
    desc = 'Renumber a vault, keeping its name (the folder moves; no note changes)',
  })

  vim.api.nvim_create_user_command('PKMVaultUnregister', function(opts)
    local vault = require('pkm.vault')

    local function ask(name)
      local entry = vault.get(name)
      if not entry then
        vim.notify(string.format('[pkm] no vault is named %q', name), vim.log.levels.ERROR)
        return
      end
      -- Confirmed even with a direct argument: this is the one command that
      -- takes a whole vault out of the set.
      require('pkm.picker').confirm({
        title = 'Unregister vault ' .. vault.folder_of(entry) .. '?',
        lines = {
          'The folder moves, intact, to:',
          '',
          '    ' .. tostring(vault.unregistered_dir()) .. '/' .. entry.name,
          '',
          'No note is deleted, and :PKMVaultAdopt ' .. entry.name .. ' is the way back.',
          'Until it is adopted its notes belong to no vault.',
        },
        on_confirm = function()
          local ok, err = vault.unregister(entry.name)
          vault_done(ok, err, entry.name .. ' moved to Unregistered/')
        end,
      })
    end

    local name = vim.trim(opts.args)
    if name ~= '' then
      ask(name)
      return
    end

    local entries = vault.list()
    if #entries == 0 then
      vim.notify('[pkm] no vaults are registered', vim.log.levels.INFO)
      return
    end
    require('pkm.picker').choose(entries, {
      title   = 'Unregister which vault?',
      display = function(row) return vault.folder_of(row) end,
    }, function(row) ask(row.name) end)
  end, {
    nargs    = '?',
    complete = function() return vault_names() end,
    desc     = 'Move a vault out of the registry into Unregistered/ (always confirms)',
  })

  vim.api.nvim_create_user_command('PKMVaultAdopt', function(opts)
    local vault = require('pkm.vault')

    local function take(folder)
      local ok, err, entry = vault.adopt(folder)
      vault_done(ok, err, string.format('%s adopted as %s', folder,
        entry and vault.folder_of(entry) or folder))
    end

    local folder = vim.trim(opts.args)
    if folder ~= '' then
      take(folder)
      return
    end

    local folders = adoptable()
    if #folders == 0 then
      vim.notify('[pkm] nothing in Unregistered/ to adopt', vim.log.levels.INFO)
      return
    end
    require('pkm.picker').choose(folders, {
      title   = 'Adopt which folder?',
      display = tostring,
    }, take)
  end, {
    nargs    = '?',
    complete = adoptable,
    desc     = 'Register a folder from Unregistered/ as a vault, contents untouched',
  })

end

return M
