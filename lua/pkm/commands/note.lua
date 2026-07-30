-- =============================================================================
-- pkm.commands.note — the note lifecycle commands
-- =============================================================================
-- Dependencies : pkm, pkm.args, pkm.notes, pkm.journal, pkm.commands.shared
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- Creation, file operations, conversion/promotion, and the title field:
-- everything that makes, names or reshapes a single note, under one command.
-- `:PKMNote <verb>` — new, relative, journal, scratch, rename, delete, import,
-- convert, promote, transpose, changetype, settitle. No argument to `new` is
-- the friendly prompt; `:PKMNote new … by=<agent>` is the one safe creation
-- path — `pkm.notes.create_new_note` allocates the next number, writes
-- schema-correct frontmatter, keeps the graph in step, and stamps the
-- authorship marker.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local focus_main_win = require('pkm.commands.shared').focus_main_win

--- Create a note from `:PKMNote new`'s parsed arguments. The type comes from a
--- closed set and the placement is a side or a window number, so neither can be
--- mistaken for the other; both are optional and order-free. `title=` and `by=`
--- are named values already split out by the parser.
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

end

return M
