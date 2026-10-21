-- =============================================================================
-- pkm.commands.tag — per-note tag CRUD, and the vault-wide bulk operations
-- =============================================================================
-- Dependencies : pkm.args, pkm.tags, pkm.picker, pkm.yaml, pkm.citations,
--                pkm.ui, pkm.telescope, pkm.commands.shared
--                (lazy, inside handlers)
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

--- The tag picker for the note in the current buffer (bare `:PKMTag add` /
--- `remove`, `<leader>ta` / `<leader>tr`). The shared `picker.select_tag` —
--- Telescope with per-tag counts and a preview of the notes carrying each tag,
--- `vim.ui.select` only without Telescope — so the vault's growing tag list is
--- never a plain window (PRINCIPLES § Design, rule 5).
---
---   add     every vault tag, ranked for THIS note (co-occurring first, its own
---           last); typing filters (case- and accent-insensitive), and text that
---           is not yet a tag is offered as "← new tag" — look, then create.
---   remove  only the tags the note carries, with their vault counts.
---
--- Both panels are for repeated use (PRINCIPLES § Design, rule 8): a note is
--- usually given or stripped of several tags at once, so the panel stays open
--- after each pick — re-ranked for the note as it now stands, prompt cleared —
--- and `<Esc>` closes it. Remove also ends by itself once no tag is left.
---
--- The note's tags are read from the buffer, not the index, so unsaved edits
--- count. The write stays buffer-only (citations.add_tag/remove_tag — no
--- index.invalidate). Since the panel keeps focus, each write runs *in* the
--- note's window (`nvim_win_call`, which fires no autocommands — so the panel is
--- not closed by a focus change) or, if that window is gone, in its buffer;
--- focus returns to the note's window when the panel ends.
---@param kind 'add'|'remove'
local function pick_buffer_tag(kind)
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local yaml = require('pkm.yaml')
  if not yaml.parse_frontmatter(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then
    vim.notify('[pkm] no frontmatter found', vim.log.levels.WARN)
    return
  end

  --- The note's tags as its buffer says right now.
  ---@return string[]
  local function note_tags()
    local fm = yaml.parse_frontmatter(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local out = {}
    if fm and type(fm.tags) == 'table' then
      for _, t in ipairs(fm.tags) do out[#out + 1] = tostring(t) end
    end
    return out
  end

  local tags   = require('pkm.tags')
  local picker = require('pkm.picker')

  local function apply(chosen)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local function write()
      require('pkm.citations')[kind == 'add' and 'add_tag' or 'remove_tag'](chosen)
    end
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_win_call(win, write)
    else
      vim.api.nvim_buf_call(buf, write)
    end
  end

  local function back_to_note()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
  end

  if kind == 'add' then
    picker.select_tag(tags.suggest_tags_for(note_tags()), {
      title     = 'Add tag to this note',
      allow_new = true,
      keep_open = true,
      refresh   = function() return tags.suggest_tags_for(note_tags()) end,
      on_close  = back_to_note,
    }, apply)
    return
  end

  -- Remove: the note's own tags, in its order, carrying their vault counts (a
  -- tag not saved to disk yet has none).
  local function own_rows()
    local by_tag = {}
    for _, row in ipairs(tags.tag_counts()) do by_tag[row.tag] = row end
    local rows, seen = {}, {}
    for _, t in ipairs(note_tags()) do
      local norm = tags.normalize(t)
      if norm and not seen[norm] then
        seen[norm] = true
        rows[#rows + 1] = by_tag[norm] or { tag = norm, count = 0, paths = {} }
      end
    end
    return rows
  end

  local rows = own_rows()
  if #rows == 0 then
    vim.notify('[pkm] no tags to remove', vim.log.levels.INFO)
    return
  end
  picker.select_tag(rows, {
    title     = 'Remove tag from this note',
    keep_open = true,
    refresh   = own_rows,
    on_close  = back_to_note,
  }, apply)
end

--- Add or remove one tag on a single note. With `note_ref` it writes to that
--- named note on disk (the typed form the agent path needs, since an agent tags
--- notes it is not "in"); without it, the buffer-only path.
---@param kind 'add'|'remove'
---@param tag string            the tag (possibly empty → open the tag picker)
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
  if tag ~= '' then
    require('pkm.citations')[kind == 'add' and 'add_tag' or 'remove_tag'](tag)
  else
    pick_buffer_tag(kind)
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
