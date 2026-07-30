-- =============================================================================
-- pkm.commands.note — the note lifecycle commands
-- =============================================================================
-- Dependencies : pkm, pkm.args, pkm.notes, pkm.journal, pkm.commands.shared
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Creation, file operations, conversion/promotion, and the title field:
-- everything that makes, names or reshapes a single note.
--
-- The whole lifecycle is reached two ways. `:PKMNote <verb>` is the context
-- form the command clearup introduces — `new`, `rename`, `delete`, `convert`,
-- `promote`, `transpose`, `changetype`, `settitle`, `import`, plus `relative`,
-- `journal`, `scratch`. The original per-operation names (`:PKMNewNote`,
-- `:PKMRenameNote`, …) stay as aliases; they will be removed once the context
-- form has shipped. Both drive the same cores, so neither can drift from the
-- other. `:PKMNote new` is the one safe creation path: `pkm.notes.create_new_note`
-- allocates the next number, writes schema-correct frontmatter, keeps the graph
-- in step and — with `by=<agent>` — stamps the authorship marker. No argument
-- is the friendly prompt, exactly as before, so human use is untouched.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local focus_main_win = require('pkm.commands.shared').focus_main_win

--- Create a note from a command's parsed arguments. Shared by `:PKMNewNote` and
--- `:PKMNote new`, which is what keeps the two forms one behaviour.
--- The type comes from a closed set and the placement is a side or a window
--- number, so neither can be mistaken for the other; both are optional and
--- order-free. `title=` and `by=` are named values already split out by the
--- parser.
---@param positional string[]  the words after the verb (types, placements)
---@param named table          { title?, by? }
local function act_new(positional, named)
  local note_type, where
  for _, arg in ipairs(positional) do
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
    where = where, title = named.title, by = named.by,
  })
end

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- :PKMNote — the context form: one verb per lifecycle operation
  -- ---------------------------------------------------------------------------
  local NOTE_VERBS = {
    'new', 'relative', 'journal', 'scratch', 'rename', 'delete',
    'import', 'convert', 'promote', 'transpose', 'changetype', 'settitle',
  }

  vim.api.nvim_create_user_command('PKMNote', function(opts)
    local p = require('pkm.args').parse(opts, {
      verbs = NOTE_VERBS, default = 'new', named = true,
    })

    -- The raw words after the verb, joined — used where the argument is free
    -- text that may contain '=' (a name, a title), so it is taken from the
    -- untouched fargs rather than the key=value-parsed positional.
    local rest = table.concat(vim.list_slice(opts.fargs, p.is_verb and 2 or 1), ' ')
    rest = rest ~= '' and rest or nil

    local v = p.verb
    if v == 'new' then
      act_new(p.positional, p.named)
    elseif v == 'relative' then
      require('pkm.notes').create_relative_note(p.positional[1])
    elseif v == 'journal' then
      focus_main_win()
      require('pkm.journal').create_entry(true)
    elseif v == 'scratch' then
      focus_main_win()
      require('pkm.notes').create_scratchpad()
    elseif v == 'rename' then
      require('pkm.notes').rename_note(rest)
    elseif v == 'delete' then
      require('pkm').delete_note_safely()
    elseif v == 'import' then
      focus_main_win()
      require('pkm.notes').import_note()
    elseif v == 'convert' then
      require('pkm.notes').convert_note()
    elseif v == 'promote' then
      require('pkm.notes').promote_note()
    elseif v == 'transpose' then
      require('pkm.notes').transpose_note()
    elseif v == 'changetype' then
      require('pkm.notes').change_note_type()
    elseif v == 'settitle' then
      require('pkm.notes').set_title(rest)
    end
  end, {
    nargs    = '*',
    complete = function(arg_lead, line)
      local out
      if line:match('^%s*PKMNote%s+[Nn][Ee][Ww]%s') then
        out = { 'note', 'agg', 'bib', 'left', 'right', 'title=', 'by=' }
      elseif line:match('^%s*PKMNote%s+[Rr][Ee][Ll][Aa][Tt][Ii][Vv][Ee]%s') then
        out = { 'note', 'agg', 'bib' }
      else
        out = NOTE_VERBS
      end
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, out)
    end,
    desc = 'The note lifecycle: :PKMNote <verb> (new/rename/delete/convert/promote/…); bare = new',
  })

  -- ---------------------------------------------------------------------------
  -- Note creation (aliases)
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
    act_new(p.positional, p.named)
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
  -- Note file operations (aliases)
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
  -- Note conversion and promotion (aliases)
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
  -- Frontmatter: the title field (buffer-only; no disk write) (alias)
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
