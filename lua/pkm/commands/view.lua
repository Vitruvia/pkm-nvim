-- =============================================================================
-- pkm.commands.view — the view surface
-- =============================================================================
-- Dependencies : pkm.args, pkm.views, pkm.citations, pkm.tags, pkm.export,
--                pkm.utils, pkm.commands.shared (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Opening views, editing membership, creating/updating/deleting them, and
-- exporting a view. :PKMView already dispatches verbs (add/remove/rename)
-- through pkm.args — the model the command clearup repeats elsewhere.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local focus_main_win = require('pkm.commands.shared').focus_main_win

local M = {}

function M.register()

  -- :PKMView [add|remove] [name] — open a view, or move the current note in or
  -- out of one. No second command: the verbs are arguments, and a bare name
  -- still means "open", so nothing that worked before reads differently now.
  vim.api.nvim_create_user_command('PKMView', function(opts)
    local views = require('pkm.views')

    -- note=<ref> is pulled out first, so it never lands in the view name; what
    -- remains is read exactly as before.
    local p        = require('pkm.args').parse(opts, { named = true })
    local note_ref = p.named.note

    -- `rename` is handled here rather than in parse_command_args, because both
    -- names can contain spaces: the old name is resolved as the longest known
    -- view among the words after `rename`, and the rest is the new name.
    if (p.positional[1] or ''):lower() == 'rename' then
      local rest = {}
      for i = 2, #p.positional do rest[#rest + 1] = p.positional[i] end
      local known = {}
      for _, v in ipairs(views.list()) do known[v] = true end

      local old, split
      for len = #rest, 1, -1 do
        local cand = table.concat(vim.list_slice(rest, 1, len), ' ')
        if known[cand] then old, split = cand, len break end
      end
      if not old then
        vim.notify('[pkm] usage: :PKMView rename <existing view> <new name>', vim.log.levels.WARN)
        return
      end
      local new = table.concat(vim.list_slice(rest, split + 1, #rest), ' ')
      if new == '' then
        vim.notify('[pkm] a new name is required', vim.log.levels.WARN)
        return
      end
      local ok, rerr = views.rename(old, new)
      if ok then
        vim.notify(string.format("[pkm] view renamed: '%s' → '%s'", old, new), vim.log.levels.INFO)
      else
        vim.notify('[pkm] ' .. (rerr or 'not renamed'), vim.log.levels.ERROR)
      end
      return
    end

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
      local out = { 'add', 'remove', 'rename' }
      vim.list_extend(out, views.list())
      return out
    end,
    desc     = 'Open a view, add/remove a note, or rename (:PKMView rename <old> <new>)',
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

end

return M
