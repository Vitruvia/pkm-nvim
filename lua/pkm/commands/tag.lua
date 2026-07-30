-- =============================================================================
-- pkm.commands.tag — tag browsing and tag writes
-- =============================================================================
-- Dependencies : pkm.args, pkm.tags, pkm.citations, pkm.ui, pkm.telescope,
--                pkm.commands.shared (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Browsing notes by tag, the batch tag operations, and the per-note tag writes.
-- :PKMAddTag/:PKMRemoveTag are buffer-only by default; with note=<ref> they
-- write to a named note on disk (the typed form the agent path needs).
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local focus_main_win = require('pkm.commands.shared').focus_main_win

local M = {}

function M.register()

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

  -- ---------------------------------------------------------------------------
  -- Per-note tag writes (buffer-only; no disk write; no index.invalidate)
  -- ---------------------------------------------------------------------------
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

end

return M
