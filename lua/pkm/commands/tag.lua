-- =============================================================================
-- pkm.commands.tag — per-note tag CRUD, and the vault-wide bulk operations
-- =============================================================================
-- Dependencies : pkm.args, pkm.tags, pkm.citations, pkm.ui, pkm.telescope,
--                pkm.commands.shared (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Two commands, singular and plural, split by scope:
--   :PKMTag  add|remove <tag> [note=<ref>] | merge   — one note (buffer or note=)
--   :PKMTags add|remove|rename <tag>                 — across ALL notes (bulk),
--                                                       with the change-list confirm
-- Browsing notes by tag is a third thing and lives on `:PKMBrowse tags`.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local focus_main_win = require('pkm.commands.shared').focus_main_win

--- Add or remove one tag on a single note. With `note_ref` it writes to that
--- named note on disk (the typed form the agent path needs, since an agent tags
--- notes it is not "in"); without it, the buffer-only path.
---@param kind 'add'|'remove'
---@param tag string            the tag (possibly empty → open the panel)
---@param note_ref string|nil   note= reference, or nil for the current buffer
local function apply_tag(kind, tag, note_ref)
  if note_ref then
    if tag == '' then
      vim.notify('[pkm] a tag is required with note=', vim.log.levels.WARN)
      return
    end
    local item, rerr = require('pkm.citations').resolve_citable(note_ref)
    if not item then
      vim.notify('[pkm] ' .. (rerr or 'note not found'), vim.log.levels.ERROR)
      return
    end
    local ops = (kind == 'add') and { add = { tag } } or { remove = { tag } }
    local ok, werr = require('pkm.tags').write_note_tags(item.path, ops)
    if ok then
      vim.notify(string.format("[pkm] %s '%s' on %s",
        kind == 'add' and 'added' or 'removed', tag, note_ref), vim.log.levels.INFO)
    else
      vim.notify('[pkm] ' .. (werr or 'not written'), vim.log.levels.ERROR)
    end
    return
  end

  -- No note=: the buffer-only path.
  -- (The empty-tag panel is still the built-in list, not a Telescope picker —
  -- see doc/CHANGELOG.md Known limitations.)
  if tag ~= '' then
    require('pkm.citations')[kind == 'add' and 'add_tag' or 'remove_tag'](tag)
  else
    require('pkm.ui').open_tag_panel(kind)
  end
end

--- Open the tag-merge screen (Telescope picker, or the ui fallback).
local function act_merge()
  if pcall(require, 'telescope') then
    require('pkm.telescope').merge_tags_picker()
  else
    require('pkm.ui').merge_tags_ui()
  end
end

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- :PKMTag — one note: add / remove / merge
  -- ---------------------------------------------------------------------------
  local TAG_VERBS = { 'add', 'remove', 'merge' }

  vim.api.nvim_create_user_command('PKMTag', function(opts)
    local p = require('pkm.args').parse(opts, { verbs = TAG_VERBS, named = true })
    local tag = table.concat(p.positional, ' ')

    if p.verb == 'add' then
      apply_tag('add', tag, p.named.note)
    elseif p.verb == 'remove' then
      apply_tag('remove', tag, p.named.note)
    elseif p.verb == 'merge' then
      act_merge()
    else
      vim.notify('[pkm] :PKMTag add|remove <tag> [note=<ref>] | merge',
        vim.log.levels.WARN)
    end
  end, {
    nargs    = '*',
    complete = function(arg_lead, line)
      local out
      if line:match('^%s*PKMTag%s+[Aa][Dd][Dd]%s')
      or line:match('^%s*PKMTag%s+[Rr][Ee][Mm][Oo][Vv][Ee]%s') then
        out = { 'note=' }
        for _, row in ipairs(require('pkm.tags').tag_counts()) do out[#out + 1] = row.tag end
      else
        out = TAG_VERBS
      end
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, out)
    end,
    desc = 'Tag one note: :PKMTag add|remove <tag> [note=<ref>] | merge',
  })

  -- ---------------------------------------------------------------------------
  -- :PKMTags — vault-wide bulk operations (add/remove/rename across ALL notes)
  -- ---------------------------------------------------------------------------
  -- The plural is the whole-vault scope: the change list is always shown, and
  -- nothing is written until it is confirmed. The per-note forms live on the
  -- singular :PKMTag; browsing notes by tag moved to :PKMBrowse tags. Bare, it
  -- offers the three bulk operations.
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
        -- Browsing moved to :PKMBrowse tags; send it there.
        vim.cmd('PKMBrowse tags')
      elseif ops then
        tags.batch_on(tags.all_note_paths(), mode, ops, header)
      else
        tags.batch_flow(mode)
      end
      return
    end

    vim.ui.select({
      'Add a tag to all notes…',
      'Remove a tag from all notes…',
      'Rename a tag across all notes…',
    }, { prompt = 'Bulk tags (whole vault):' }, function(_, idx)
      if idx == 1 then tags.batch_flow('add')
      elseif idx == 2 then tags.batch_flow('remove')
      elseif idx == 3 then tags.batch_flow('rename')
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
        candidates = { 'add', 'remove', 'rename' }
      elseif words[2] == 'remove' or words[2] == 'rename' then
        for _, row in ipairs(require('pkm.tags').tag_counts()) do
          candidates[#candidates + 1] = row.tag
        end
      end

      return vim.tbl_filter(function(c)
        return c:find(arg_lead, 1, true) == 1
      end, candidates)
    end,
    desc = 'Bulk tag ops across ALL notes: :PKMTags add|remove|rename <tag> (change-list confirm)',
  })

end

return M
