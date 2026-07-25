-- =============================================================================
-- pkm.picker — Note selection and confirmation front-ends
-- =============================================================================
-- Dependencies : pkm.utils, pkm.yaml (lazy), pkm.index (lazy), telescope (optional)
-- Consumed by  : pkm.export (results picker), pkm.tags (tag picker, batch flow)
--
-- Two front-ends, one gesture. Every operation that acts on a *set* of notes
-- goes through select(): filter first, then mark with <Tab>, then confirm.
-- Whether Telescope is installed changes nothing about that gesture — this
-- module is the only place that knows which of the two is in play.
--
-- Selection rule, shared by both front-ends: <CR> with nothing marked confirms
-- **everything currently listed**, which is what the title counts. Marking with
-- <Tab> narrows the confirmation to the marks. Typing in the Telescope prompt
-- filters by exact substring (never fuzzy) and therefore also narrows what an
-- unmarked <CR> confirms.
--
-- That one gesture is why a batch preview is not a screen of its own: the
-- "before → after" list is just select() with a different row renderer
-- (opts.display), so marking never flips meaning between screens.
--
-- No function here writes anything: they collect an answer and hand it to a
-- callback. What the caller does with it — copy, retag, delete — is the
-- caller's business.
--
-- Public API:
--   select(paths, opts, on_confirm)   → note picker; on_confirm(string[] paths)
--   select_tag(rows, opts, on_choice) → tag picker with counts, optionally
--                                       creating what is typed; on_choice(tag)
--   confirm(opts)                     → scrollable list + <CR>/q; no selection
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: Row rendering
-- =============================================================================

--- Display string for one note row: "<filename>  [tag1, tag2]".
--- Tags are shown with the spelling stored in the file, not the index's
--- normalised copy, so the row matches what the note actually says.
---@param path string
---@return string
local function build_display(path)
  local name  = vim.fn.fnamemodify(path, ':t')
  local lines = utils.read_lines(path)
  local fm    = lines and require('pkm.yaml').parse_frontmatter(lines) or nil

  local tags = {}
  if fm and type(fm.tags) == 'table' then
    for _, t in ipairs(fm.tags) do
      if type(t) == 'string' then tags[#tags + 1] = t end
    end
  end

  return name .. (#tags > 0 and ('  [' .. table.concat(tags, ', ') .. ']') or '')
end

--- Compose the title both front-ends show.
---@param title string   Caller's label, e.g. 'PKMExport'
---@param count integer
---@param hint  string   What <CR> does, e.g. 'export listed'
---@return string
local function title_line(title, count, hint)
  return string.format('%s:  %d note%s  ·  <Tab> mark subset  ·  <CR> %s',
    title, count, count == 1 and '' or 's', hint)
end

--- Right-pad to a display width, counting columns rather than bytes so that
--- accented tags ("língua-portuguesa") line up with plain ASCII ones.
---@param text  string
---@param width integer
---@return string
local function pad_to(text, width)
  return text .. string.rep(' ', math.max(width - vim.fn.strdisplaywidth(text), 0))
end

--- Preview body for one tag: the notes carrying it, title first.
--- Read from the index, so it costs nothing beyond what is already in memory.
---@param row table  { tag, count, paths }
---@return string[]
local function tag_preview_lines(row)
  local index = require('pkm.index')

  if row.is_new then
    return { '# ' .. row.tag, '', 'New tag — no note carries it yet.' }
  end

  local lines = {
    '# ' .. row.tag,
    '',
    string.format('%d note%s', row.count, row.count == 1 and '' or 's'),
    '',
  }
  if row.note then table.insert(lines, 3, row.note) end

  for _, path in ipairs(row.paths) do
    local entry = index.get(path)
    lines[#lines + 1] = string.format('%s %s',
      utils.type_prefix(entry and entry.note_type or nil),
      (entry and entry.title ~= '' and entry.title) or vim.fn.fnamemodify(path, ':t:r'))
    lines[#lines + 1] = '      ' .. vim.fn.fnamemodify(path, ':t')
  end

  return lines
end

-- =============================================================================
-- SECTION: Telescope front-end
-- =============================================================================

---@param paths      string[]
---@param opts       table     { title, hint, display, on_cancel? }
---@param on_confirm function(paths: string[])
local function telescope_select(paths, opts, on_confirm)
  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers   = require('telescope.previewers')
  local sorters      = require('telescope.sorters')

  -- Built once; the dynamic finder filters this table on every keystroke.
  local entries = {}
  for _, path in ipairs(paths) do
    local display = opts.display(path)
    entries[#entries + 1] = {
      value   = path,
      display = display,
      ordinal = display,
      path    = path,   -- required by the vim_buffer_cat previewer
    }
  end

  --- Entries the prompt currently leaves visible. Shared by the finder and the
  --- confirm action, so "everything listed" cannot drift from what is on screen.
  ---@param prompt string|nil
  ---@return table[]
  local function visible_entries(prompt)
    if not prompt or prompt == '' then return entries end
    local needle   = prompt:lower()
    local filtered = {}
    for _, e in ipairs(entries) do
      if e.ordinal:lower():find(needle, 1, true) then filtered[#filtered + 1] = e end
    end
    return filtered
  end

  pickers.new({}, {
    prompt_title = title_line(opts.title, #entries, opts.hint)
      .. '  ·  type for exact filter',

    finder = finders.new_dynamic({
      fn          = visible_entries,
      entry_maker = function(e) return e end,
    }),

    -- Pass-through sorter: always score 0, so Telescope cannot reintroduce a
    -- fuzzy pass on top of the exact substring filter above.
    sorter = sorters.Sorter:new({ scoring_function = function() return 0 end }),

    previewer = previewers.vim_buffer_cat.new({}),

    attach_mappings = function(prompt_bufnr, map)
      local sel_next = actions.toggle_selection + actions.move_selection_next
      local sel_prev = actions.toggle_selection + actions.move_selection_previous
      map('i', '<Tab>',   sel_next)
      map('n', '<Tab>',   sel_next)
      map('i', '<S-Tab>', sel_prev)
      map('n', '<S-Tab>', sel_prev)

      actions.select_default:replace(function()
        local picker     = action_state.get_current_picker(prompt_bufnr)
        local selections = picker:get_multi_selection()
        if #selections == 0 then
          selections = visible_entries(action_state.get_current_line())
        end

        actions.close(prompt_bufnr)

        if #selections == 0 then
          vim.notify('[pkm] nothing listed to act on', vim.log.levels.INFO)
          return
        end

        local chosen = {}
        for _, sel in ipairs(selections) do chosen[#chosen + 1] = sel.value end
        vim.schedule(function() on_confirm(chosen) end)
      end)

      return true
    end,
  }):find()
end

--- Display string for one tag row, padded so the counts line up.
---@param row   table    { tag, count, note? }
---@param width integer
---@return string
local function tag_display(row, width)
  if row.is_new then
    return string.format("%s  ← new tag", pad_to(row.tag, width))
  end
  return string.format('%s  (%d note%s)%s',
    pad_to(row.tag, width), row.count, row.count == 1 and '' or 's',
    row.note and ('  ·  ' .. row.note) or '')
end

---@param rows      table[]   { { tag, count, paths, note? }, … }
---@param opts      table     { title, allow_new? }
---@param on_choice function(tag: string)
local function telescope_select_tag(rows, opts, on_choice)
  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers   = require('telescope.previewers')
  local sorters      = require('telescope.sorters')

  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, vim.fn.strdisplaywidth(row.tag))
  end

  --- Rows the prompt leaves visible, plus — when the caller allows it and the
  --- typed text is not already a tag — the option to create that tag.
  ---@param prompt string|nil
  ---@return table[]
  local function visible_rows(prompt)
    if not prompt or prompt == '' then return rows end

    local needle, filtered, exact = prompt:lower(), {}, false
    for _, row in ipairs(rows) do
      if row.tag:lower():find(needle, 1, true) then filtered[#filtered + 1] = row end
      if row.tag:lower() == needle then exact = true end
    end

    if opts.allow_new and not exact then
      local tag = prompt:match('^%s*(.-)%s*$'):lower()
      if tag ~= '' then
        table.insert(filtered, 1, { tag = tag, count = 0, paths = {}, is_new = true })
      end
    end

    return filtered
  end

  pickers.new({}, {
    prompt_title = string.format('%s:  %d tag%s%s',
      opts.title, #rows, #rows == 1 and '' or 's',
      opts.allow_new and '  ·  type to create' or ''),

    finder = finders.new_dynamic({
      fn = visible_rows,
      entry_maker = function(row)
        return {
          value   = row,
          ordinal = row.tag,
          display = tag_display(row, width),
        }
      end,
    }),

    -- Pass-through: the caller's order is meaningful (context ranking), so
    -- nothing here may re-sort it.
    sorter = sorters.Sorter:new({ scoring_function = function() return 0 end }),

    previewer = previewers.new_buffer_previewer({
      title = 'Notes with this tag',
      define_preview = function(self, entry)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false,
          tag_preview_lines(entry.value))
        vim.api.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
      end,
    }),

    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then vim.schedule(function() on_choice(sel.value.tag) end) end
      end)
      return true
    end,
  }):find()
end

-- =============================================================================
-- SECTION: Float front-end (no Telescope)
-- =============================================================================

--- Open a scrollable, read-only float over `lines` and wire confirm/cancel.
---@param title      string
---@param lines      string[]
---@param on_confirm function()
---@param on_cancel  function|nil
local function float_window(title, lines, on_confirm, on_cancel)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false,  { buf = buf })
  vim.api.nvim_set_option_value('bufhidden',  'wipe', { buf = buf })

  local width  = math.min(82, vim.o.columns - 4)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.7))
  local win    = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    width     = width,
    height    = height,
    col       = math.floor((vim.o.columns - width)  / 2),
    row       = math.floor((vim.o.lines   - height) / 2),
    style     = 'minimal',
    border    = 'rounded',
    title     = ' ' .. title .. ' ',
    title_pos = 'center',
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  local ko = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set('n', '<CR>', function() close(); on_confirm() end, ko)
  for _, lhs in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', lhs, function()
      close()
      if on_cancel then on_cancel() end
    end, ko)
  end
end

-- =============================================================================
-- SECTION: Public API
-- =============================================================================

--- Pick notes from a list and hand the confirmed subset to on_confirm.
--- Telescope when available (filter as you type, `<Tab>` to mark), the float
--- fallback otherwise (whole list, `<CR>` confirms all).
---
--- `opts.display` renders one row. It defaults to filename + tags; a batch
--- preview passes its own renderer so the same picker shows "before → after"
--- without changing what marking and `<CR>` mean.
---@param paths      string[]  Candidates, already collected by the caller
---@param opts       table     { title, hint, display? = function(path)→string, on_cancel? }
---@param on_confirm function(paths: string[])
function M.select(paths, opts, on_confirm)
  opts = opts or {}
  opts.title   = opts.title   or 'PKM'
  opts.hint    = opts.hint    or 'confirm'
  opts.display = opts.display or build_display

  if #paths == 0 then
    vim.notify('[pkm] no notes to choose from', vim.log.levels.INFO)
    return
  end

  if pcall(require, 'telescope') then
    telescope_select(paths, opts, on_confirm)
    return
  end

  local header = '  ' .. title_line(opts.title, #paths, opts.hint)
    .. '  ·  q/<Esc> cancel'
  local lines  = { header, '  ' .. string.rep('─', math.max(#header - 2, 10)) }
  for _, p in ipairs(paths) do
    lines[#lines + 1] = '  • ' .. opts.display(p)
  end

  float_window(opts.title, lines,
    function() vim.schedule(function() on_confirm(paths) end) end,
    opts.on_cancel)
end

--- Pick one tag from a counted list and hand it to on_choice.
--- Telescope shows the note count beside each tag, the caller's optional `note`
--- (why this tag is being suggested), and previews the notes that carry it;
--- without Telescope it degrades to `vim.ui.select`. The caller builds the rows
--- (see `tags.tag_counts` / `tags.suggest_tags`) and their order is preserved
--- exactly — which is what keeps this module free of any tag knowledge.
---
--- With `opts.allow_new`, typing a tag that does not exist offers to create it:
--- the same screen answers "which of my tags?" and "a new one, this".
---@param rows      table[]  { { tag, count, paths, note? }, … }
---@param opts      table    { title = string, allow_new? = boolean }
---@param on_choice function(tag: string)
function M.select_tag(rows, opts, on_choice)
  opts = opts or {}
  opts.title = opts.title or 'Tags'

  if #rows == 0 and not opts.allow_new then
    vim.notify('[pkm] no tags to choose from', vim.log.levels.INFO)
    return
  end

  if pcall(require, 'telescope') then
    telescope_select_tag(rows, opts, on_choice)
    return
  end

  --- Free text, for the fallback's "new tag" entry and for an empty list.
  local function ask_new()
    vim.ui.input({ prompt = 'New tag: ' }, function(text)
      local tag = text and text:match('^%s*(.-)%s*$'):lower()
      if not tag or tag == '' then return end
      vim.schedule(function() on_choice(tag) end)
    end)
  end

  if #rows == 0 then
    ask_new()
    return
  end

  local items = {}
  if opts.allow_new then items[1] = { is_new_prompt = true } end
  for _, row in ipairs(rows) do items[#items + 1] = row end

  vim.ui.select(items, {
    prompt      = opts.title,
    format_item = function(item)
      if item.is_new_prompt then return '+ new tag…' end
      return string.format('%s  (%d note%s)%s',
        item.tag, item.count, item.count == 1 and '' or 's',
        item.note and ('  ·  ' .. item.note) or '')
    end,
  }, function(item)
    if not item then return end
    if item.is_new_prompt then
      vim.schedule(ask_new)
    else
      vim.schedule(function() on_choice(item.tag) end)
    end
  end)
end

--- Show a read-only list and ask for confirmation. No selection, no marks:
--- `<CR>` accepts the whole thing, `q`/`<Esc>` backs out. For an all-or-nothing
--- gate over a change the user cannot usefully narrow — where select() would
--- promise a per-note choice the operation does not have.
---@param opts table  { title, lines, on_confirm, on_cancel? }
function M.confirm(opts)
  float_window(opts.title or 'PKM', opts.lines or {},
    opts.on_confirm or function() end, opts.on_cancel)
end

return M
