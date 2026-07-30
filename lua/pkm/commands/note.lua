-- =============================================================================
-- pkm.commands.note — the note lifecycle commands
-- =============================================================================
-- Dependencies : pkm.args, pkm.notes, pkm.journal, pkm.commands.shared (lazy)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Creation, file operations, conversion/promotion, and the title field:
-- everything that makes, names or reshapes a single note.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local focus_main_win = require('pkm.commands.shared').focus_main_win

local M = {}

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

    require('pkm.notes').create_new_note(note_type, {
      where = where, title = p.named.title, by = p.named.by,
    })
  end, {
    nargs    = '*',
    complete = function(lead)
      local out = {}
      for _, tok in ipairs({ 'note', 'agg', 'bib', 'left', 'right', 'title=', 'by=' }) do
        if tok:find(lead:lower(), 1, true) == 1 then out[#out + 1] = tok end
      end
      return out
    end,
    desc = 'Create a note; optional type, placement, title=<text> and by=<agent>',
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
  -- Frontmatter: the title field (buffer-only; no disk write)
  -- ---------------------------------------------------------------------------
  -- The whole argument string is the title, so a spaced title needs no quoting;
  -- with no argument it prompts, seeded with the current title.
  vim.api.nvim_create_user_command('PKMSetTitle', function(opts)
    require('pkm.notes').set_title(opts.args ~= '' and opts.args or nil)
  end, {
    nargs = '*',
    desc  = 'Set the title frontmatter field (argument = title; prompts if none; no disk write)',
  })

end

return M
