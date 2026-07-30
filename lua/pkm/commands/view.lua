-- =============================================================================
-- pkm.commands.view — the view surface
-- =============================================================================
-- Dependencies : pkm.args, pkm.views, pkm.citations, pkm.tags, pkm.export,
--                pkm.utils, pkm.commands.shared (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- The whole view surface reached two ways. `:PKMView <verb>` is the context
-- form: a bare view name opens it (the default), and the verbs are add, remove,
-- rename, new, update, edit, delete, last, export, sidebar, list. The original
-- names (`:PKMViews`, `:PKMViewNew`, `:PKMViewUpdate`, …) stay as aliases and
-- drive the same cores. Membership (add/remove) still goes through
-- views.parse_command_args, so a view named like a verb still opens.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local focus_main_win = require('pkm.commands.shared').focus_main_win

--- Open the panel listing all defined views.
local function act_views_panel()
  require('pkm.views').open_views_panel()
end

--- Create a new view (simple or subproject), prompting through the choice.
local function act_view_new()
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
            -- trivially reversible (delete it, or :PKMView update to fix a
            -- wrong parameter) — confirmation stays reserved for actually
            -- dangerous actions (deletion, everywhere else in this file).
            views.save_subproject(name, parent, expr)
          end)
        end)
      end
    end)
  end)
end

--- Edit an existing view (expression pre-filled). A nil name prompts/picks.
local function act_view_update(name)
  require('pkm.views').edit_view(name)
end

--- Open views.json for direct editing.
local function act_view_edit()
  focus_main_win()
  local path = require('pkm.utils').join(require('pkm').config.root_path, 'views.json')
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({ '{}' }, path)
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

--- Delete a view: the panel when unnamed, a confirmed delete when named.
local function act_view_delete(name)
  if not name then
    require('pkm.views').open_view_deletion_panel()
    return
  end
  -- Direct-argument fast path retains its own confirmation — "deletion always
  -- confirmed" applies here too, not just to the panel.
  local choice = vim.fn.confirm(
    string.format("Delete view '%s'?", name), '&Yes\n&No', 2)
  if choice == 1 then
    require('pkm.views').delete(name)
  end
end

--- Reopen the last activated view (session-scoped).
local function act_view_last()
  focus_main_win()
  require('pkm.views').open_last()
end

--- Export all notes in a named view (a picker when unnamed).
local function act_view_export(name)
  local views = require('pkm.views')
  if not name then
    vim.ui.select(views.list(), { prompt = 'Export view:' }, function(sel)
      if sel then
        require('pkm.export').export_direct(sel, views.match_all(sel))
      end
    end)
    return
  end
  require('pkm.export').export_direct(name, views.match_all(name))
end

--- Open or toggle the persistent view sidebar (optionally a named view).
local function act_view_sidebar(name)
  require('pkm.views').open_sidebar(name)
end

--- Rename a view, resolving a spaced old name as the longest known view among
--- the words after `rename`, the rest being the new name.
local function act_view_rename(rest_words)
  local views = require('pkm.views')
  local known = {}
  for _, v in ipairs(views.list()) do known[v] = true end

  local old, split
  for len = #rest_words, 1, -1 do
    local cand = table.concat(vim.list_slice(rest_words, 1, len), ' ')
    if known[cand] then old, split = cand, len break end
  end
  if not old then
    vim.notify('[pkm] usage: :PKMView rename <existing view> <new name>', vim.log.levels.WARN)
    return
  end
  local new = table.concat(vim.list_slice(rest_words, split + 1, #rest_words), ' ')
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
end

local M = {}

function M.register()

  -- The lifecycle verbs (new/update/edit/delete/last/export/sidebar/list) and
  -- rename are intercepted ahead of the open/add/remove parser; add/remove stay
  -- with views.parse_command_args, so a view named "add" still opens.

  -- :PKMView [add|remove|<lifecycle verb>] [name] — open a view, move the current
  -- note in or out of one, or run a lifecycle verb. A bare name still means
  -- "open", so nothing that worked before reads differently now.
  vim.api.nvim_create_user_command('PKMView', function(opts)
    local views = require('pkm.views')

    -- note=<ref> is pulled out first, so it never lands in the view name; what
    -- remains is read exactly as before.
    local p        = require('pkm.args').parse(opts, { named = true })
    local note_ref = p.named.note
    local v1       = (p.positional[1] or ''):lower()
    local rest     = table.concat(vim.list_slice(p.positional, 2), ' ')
    rest = rest ~= '' and rest or nil

    if v1 == 'rename' then
      act_view_rename(vim.list_slice(p.positional, 2))
      return
    elseif v1 == 'new' then
      act_view_new(); return
    elseif v1 == 'update' then
      act_view_update(rest); return
    elseif v1 == 'edit' then
      act_view_edit(); return
    elseif v1 == 'delete' then
      act_view_delete(rest); return
    elseif v1 == 'last' then
      act_view_last(); return
    elseif v1 == 'export' then
      act_view_export(rest); return
    elseif v1 == 'sidebar' then
      act_view_sidebar(rest); return
    elseif v1 == 'list' then
      act_views_panel(); return
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
    complete = function(arg_lead, line)
      local views = require('pkm.views')
      -- After a verb that takes a view name, only view names make sense.
      if line:match('^%s*PKMView%s+[Aa][Dd][Dd]%s')
      or line:match('^%s*PKMView%s+[Rr][Ee][Mm][Oo][Vv][Ee]%s')
      or line:match('^%s*PKMView%s+[Uu][Pp][Dd][Aa][Tt][Ee]%s')
      or line:match('^%s*PKMView%s+[Dd][Ee][Ll][Ee][Tt][Ee]%s')
      or line:match('^%s*PKMView%s+[Ee][Xx][Pp][Oo][Rr][Tt]%s')
      or line:match('^%s*PKMView%s+[Ss][Ii][Dd][Ee][Bb][Aa][Rr]%s')
      or line:match('^%s*PKMView%s+[Rr][Ee][Nn][Aa][Mm][Ee]%s') then
        return views.list()
      end
      local out = { 'add', 'remove', 'rename', 'new', 'update', 'edit',
                    'delete', 'last', 'export', 'sidebar', 'list' }
      vim.list_extend(out, views.list())
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, out)
    end,
    desc     = 'Views: :PKMView [<name>] | add|remove|new|update|edit|delete|last|export|sidebar|list|rename',
  })

  -- ---------------------------------------------------------------------------
  -- Aliases
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMViews', function()
    act_views_panel()
  end, { desc = 'Browse all defined views (panel; <Tab> to browse all notes)' })

  vim.api.nvim_create_user_command('PKMViewNew', function()
    act_view_new()
  end, { desc = 'Create a new view; prompts to edit if the name already exists' })

  vim.api.nvim_create_user_command('PKMViewUpdate', function(opts)
    act_view_update(opts.args ~= '' and opts.args or nil)
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Edit an existing view (expression pre-filled; <C-r> to reset)',
  })

  vim.api.nvim_create_user_command('PKMViewEdit', function()
    act_view_edit()
  end, { desc = 'Open views.json for direct editing' })

  vim.api.nvim_create_user_command('PKMViewDelete', function(opts)
    act_view_delete(opts.args ~= '' and opts.args or nil)
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Delete a named project view (panel if no argument; confirms either way)',
  })

  vim.api.nvim_create_user_command('PKMViewLast', function()
    act_view_last()
  end, { desc = 'Reopen the last activated view (session-scoped)' })

  vim.api.nvim_create_user_command('PKMExportView', function(opts)
    act_view_export(opts.args ~= '' and opts.args or nil)
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Export all notes in a named view',
  })

  vim.api.nvim_create_user_command('PKMViewSidebar', function(opts)
    act_view_sidebar(opts.args ~= '' and opts.args or nil)
  end, {
    nargs    = '?',
    complete = function() return require('pkm.views').list() end,
    desc     = 'Open or toggle the persistent view sidebar',
  })

end

return M
