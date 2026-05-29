-- =============================================================================
-- pkm.export — Note filtering and copy utility
-- =============================================================================
-- Dependencies : pkm.utils, pkm.filter (lazy), pkm.index (lazy),
--                pkm.yaml (lazy, fallback only), pkm.init (for config),
--                telescope (optional)
-- Consumed by  : pkm.commands (:PKMExport)
--
-- READ-ONLY — never modifies any note file.
--
-- Filter semantics: the public API accepts the legacy filter table format
-- {tags_any, tags_all, title, text} for backward compatibility. Internally
-- this is converted to a filter.lua tree via filter.from_legacy() and
-- evaluated with filter.eval(). See pkm.filter for the full DSL.
--
-- All string matching is exact substring (case-insensitive, plain=true,
-- never fuzzy) as enforced by filter.eval().
--
-- Public API:
--   match_file(path, filters)  → boolean — test one file against filters
--   collect_files(filters)     → string[] — all matching paths, sorted
--   copy_files(paths, dest)    → (copied, errors) — copy to destination
--   export(filters, dest)      → programmatic no-UI entry point
--   interactive_export()       → full UI: filter form → picker → copy
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- ============================================================================
-- SHARED UTILITIES
-- ============================================================================

--- Pure-Lua binary-safe copy. No system calls; works on Windows/WSL.
--- @param src string
--- @param dst string
--- @return boolean ok
--- @return string|nil err
local function copy_file(src, dst)
  local rf, err_r = io.open(src, "rb")
  if not rf then return false, "Cannot read: " .. (err_r or src) end
  local data = rf:read("*a")
  rf:close()
  local wf, err_w = io.open(dst, "wb")
  if not wf then return false, "Cannot write: " .. (err_w or dst) end
  wf:write(data)
  wf:close()
  return true, nil
end

local function ensure_dir(dir)
  vim.fn.mkdir(dir, "p")
  return vim.fn.isdirectory(dir) == 1
end

--- Returns frontmatter table, content_start line, and raw lines for a file.
--- All three are nil if the file is unreadable or has no frontmatter.
--- @param path string
--- @return table|nil  fm
--- @return number|nil content_start
--- @return table|nil  lines
local function get_file_data(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then return nil, nil, nil end
  local fm, cs = require('pkm.yaml').parse_frontmatter(lines)
  if not fm then return nil, nil, nil end
  return fm, cs, lines
end

--- Split a comma-separated string into trimmed, non-empty tokens.
--- @param str string
--- @return table
local function split_csv(str)
  local result = {}
  for item in str:gmatch("[^,]+") do
    local t = item:match("^%s*(.-)%s*$")
    if t ~= "" then table.insert(result, t) end
  end
  return result
end

-- ============================================================================
-- FILTER ENGINE
-- ============================================================================

--- Test whether a single note file satisfies all active filters.
--- Consults the index first; falls back to reading the file directly if the
--- index does not have an entry for this path (e.g. before first save).
--- A nil or empty filters table is inactive and always returns true.
---@param path    string  Absolute path to note file
---@param filters table   Legacy filter table {tags_any?, tags_all?, title?, text?}
---@return boolean
function M.match_file(path, filters)
  local filter_mod = require('pkm.filter')
  local tree       = filter_mod.from_legacy(filters or {})
  if not tree then return true end

  local entry = require('pkm.index').get(path)
  if not entry then return false end

  return filter_mod.eval(tree, entry)
end

--- Collect all notes that satisfy filters, using the in-memory index.
--- Scope is identical to before: consolidated, journal, and scratchpad only
--- (the index itself excludes the templates folder).
---@param filters table  Legacy filter table {tags_any?, tags_all?, title?, text?}
---@return string[]  Sorted list of absolute paths
function M.collect_files(filters)
  local filter_mod = require('pkm.filter')
  local tree       = filter_mod.from_legacy(filters or {})
  local entries    = require('pkm.index').get_all()
  local matched    = {}

  for _, entry in ipairs(entries) do
    if not tree or filter_mod.eval(tree, entry) then
      matched[#matched + 1] = entry.path
    end
  end

  table.sort(matched, function(a, b)
    return vim.fn.fnamemodify(a, ":t") < vim.fn.fnamemodify(b, ":t")
  end)
  return matched
end

-- ============================================================================
-- COPY ENGINE
-- ============================================================================

--- Copy a list of files into dest directory. Reports results via vim.notify.
---@param paths string[]
---@param dest string Destination directory path
---@return integer copied Number of files successfully copied
---@return integer errors Number of files that failed
function M.copy_files(paths, dest)
  if not ensure_dir(dest) then
    vim.notify("PKMExport: Cannot create destination: " .. dest, vim.log.levels.ERROR)
    return 0, #paths
  end

  local copied, errors = 0, 0
  for _, src in ipairs(paths) do
    local filename = vim.fn.fnamemodify(src, ":t")
    local ok, err  = copy_file(src, utils.join(dest, filename))
    if ok then
      copied = copied + 1
    else
      errors = errors + 1
      vim.notify("PKMExport: " .. (err or "Failed: " .. filename), vim.log.levels.WARN)
    end
  end

  local msg = string.format(
    "PKMExport: %d note%s → %s", copied, copied == 1 and "" or "s", dest)
  if errors > 0 then
    msg = msg .. string.format(" (%d error%s)", errors, errors == 1 and "" or "s")
  end
  vim.notify(msg, errors > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
  return copied, errors
end

--- Programmatic export without UI. Collects matching files and copies them.
--- Example: require('pkm.export').export({tags_all={"math"}}, "/tmp/out")
---@param filters table
---@param dest string
function M.export(filters, dest)
  local paths = M.collect_files(filters)
  if #paths == 0 then
    vim.notify("PKMExport: No notes matched.", vim.log.levels.INFO)
    return
  end
  M.copy_files(paths, dest)
end

-- ============================================================================
-- DESTINATION PROMPT  (shared between both UI paths)
-- ============================================================================

--- Prompt for a destination path and copy on confirmation.
--- @param paths        table
--- @param default_dest string
local function prompt_dest_and_copy(paths, default_dest)
  vim.ui.input(
    { prompt  = string.format(
        "Export %d note%s to: ", #paths, #paths == 1 and "" or "s"),
      default = default_dest },
    function(dest)
      if not dest or dest:match("^%s*$") then
        vim.notify("PKMExport: Cancelled.", vim.log.levels.INFO)
        return
      end
      M.copy_files(paths, dest)
    end
  )
end

-- ============================================================================
-- FILTER FORM
-- ============================================================================

-- Field definitions. Order determines display order in the form.
-- `multi` = true: value parsed as comma-separated list.
local FIELDS = {
  { key = "tags_any", label = "Tags ANY  (OR)", multi = true  },
  { key = "tags_all", label = "Tags ALL (AND)", multi = true  },
  { key = "title",    label = "Title contains", multi = false },
  { key = "text",     label = "Text  contains", multi = false },
}

-- The literal string separating the label from the editable value.
-- The value may contain anything; we split only on the first occurrence.
local FIELD_SEP = " : "

--- Extract the value portion from a form field line.
--- Splits on the first occurrence of FIELD_SEP.
--- @param line string
--- @return string  Trimmed value, may be ""
local function extract_value(line)
  local sep_pos = line:find(FIELD_SEP, 1, true)
  if not sep_pos then return "" end
  local raw = line:sub(sep_pos + #FIELD_SEP)
  return raw:match("^%s*(.-)%s*$") or ""
end

--- Open the filter form and call on_submit(filters) when the user confirms.
--- on_submit is not called if the user cancels.
--- @param on_submit function(filters: table)
local function show_filter_form(on_submit)
  local header = {
    "  Fill in any fields. Leave blank to skip.",
    "  Comma-separated values: OR logic (or AND for the second tags field).",
    "  <Tab>/<S-Tab> move fields   <CR> search   <Esc> cancel",
    "  " .. string.rep("─", 62),
  }

  local field_start = #header + 1

  local initial_lines = vim.deepcopy(header)
  for _, f in ipairs(FIELDS) do
    table.insert(initial_lines, "  " .. f.label .. FIELD_SEP)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
  vim.api.nvim_set_option_value('modifiable', true,   { buf = buf })
  vim.api.nvim_set_option_value('bufhidden',  'wipe', { buf = buf })

  local width  = 68
  local height = #initial_lines + 2
  local win    = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    width     = width,
    height    = height,
    col       = math.floor((vim.o.columns - width)  / 2),
    row       = math.floor((vim.o.lines   - height) / 2),
    style     = 'minimal',
    border    = 'rounded',
    title     = ' PKMExport: Advanced Filter ',
    title_pos = 'center',
  })

  --- Move cursor to end of the value area on the given field line.
  local function go_to_field(idx)
    local lnum = field_start + idx - 1
    local line  = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    vim.api.nvim_win_set_cursor(win, { lnum, #line })
    vim.cmd("startinsert!")
  end

  go_to_field(1)

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function read_and_submit()
    local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local filters   = {}

    for i, field in ipairs(FIELDS) do
      local line  = buf_lines[field_start + i - 1] or ""
      local value = extract_value(line)
      if value ~= "" then
        if field.multi then
          local items = split_csv(value)
          if #items > 0 then filters[field.key] = items end
        else
          filters[field.key] = value
        end
      end
    end

    close()
    vim.schedule(function() on_submit(filters) end)
  end

  local ko = { noremap = true, silent = true, buffer = buf }

  vim.keymap.set({ 'n', 'i' }, '<CR>', function()
    vim.cmd("stopinsert")
    read_and_submit()
  end, ko)

  vim.keymap.set('n', '<Esc>', function() close() end, ko)

  vim.keymap.set({ 'n', 'i' }, '<Tab>', function()
    vim.cmd("stopinsert")
    local cur        = vim.api.nvim_win_get_cursor(win)
    local cur_field  = cur[1] - field_start + 1
    local next_field = (cur_field % #FIELDS) + 1
    go_to_field(next_field)
  end, ko)

  vim.keymap.set({ 'n', 'i' }, '<S-Tab>', function()
    vim.cmd("stopinsert")
    local cur        = vim.api.nvim_win_get_cursor(win)
    local cur_field  = cur[1] - field_start + 1
    local prev_field = ((cur_field - 2) % #FIELDS) + 1
    go_to_field(prev_field)
  end, ko)
end

-- ============================================================================
-- TELESCOPE RESULTS PICKER
-- ============================================================================

--- Build the display / ordinal string for a picker row.
--- Format: "<filename>  [tag1, tag2]"
--- Status is intentionally excluded (being removed from metadata).
local function build_display(path, fm)
  local name = vim.fn.fnamemodify(path, ":t")
  local tags  = {}
  if type(fm.tags) == "table" then
    for _, t in ipairs(fm.tags) do
      if type(t) == "string" then table.insert(tags, t) end
    end
  end
  local tag_str = #tags > 0 and ("  [" .. table.concat(tags, ", ") .. "]") or ""
  return name .. tag_str
end

--- Open a Telescope picker over a pre-filtered list of files.
---
--- The list shown is exactly what `collect_files` returned; no fzy applied.
--- Typing in the prompt runs exact substring filtering (via new_dynamic) on
--- the display string. The sorter is a pass-through (score 0 always) so it
--- cannot reintroduce fzy behaviour regardless of Telescope version.
---
--- @param paths        table   Pre-filtered list of absolute paths
--- @param default_dest string
local function telescope_results_picker(paths, default_dest)
  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers   = require('telescope.previewers')
  local sorters      = require('telescope.sorters')

  -- Build entry table once; new_dynamic will filter it on each keystroke.
  local entries = {}
  for _, path in ipairs(paths) do
    local fm, _, _ = get_file_data(path)
    fm = fm or {}
    local display = build_display(path, fm)
    table.insert(entries, {
      value   = path,
      display = display,
      ordinal = display,
      path    = path,   -- required by vim_buffer_cat previewer
    })
  end

  local count = #entries

  pickers.new({}, {
    prompt_title = string.format(
      "PKMExport: %d match%s  ·  type for exact filter  ·  <Tab> select  ·  <CR> confirm",
      count, count == 1 and "" or "es"),

    -- new_dynamic re-runs fn on every prompt change.
    -- Exact substring matching (plain=true) guarantees no fzy behaviour.
    finder = finders.new_dynamic({
      fn = function(prompt)
        if not prompt or prompt == "" then
          return entries
        end
        local needle   = prompt:lower()
        local filtered = {}
        for _, e in ipairs(entries) do
          if e.ordinal:lower():find(needle, 1, true) then
            table.insert(filtered, e)
          end
        end
        return filtered
      end,
      entry_maker = function(e) return e end,
    }),

    -- Pass-through sorter: always returns score 0 (keep, no reordering).
    -- This prevents Telescope from applying any secondary fzy pass.
    sorter = sorters.Sorter:new({
      scoring_function = function() return 0 end,
    }),

    previewer = previewers.vim_buffer_cat.new({}),

    attach_mappings = function(prompt_bufnr, map)
      local sel_next = actions.toggle_selection + actions.move_selection_next
      local sel_prev = actions.toggle_selection + actions.move_selection_previous
      map("i", "<Tab>",   sel_next)
      map("n", "<Tab>",   sel_next)
      map("i", "<S-Tab>", sel_prev)
      map("n", "<S-Tab>", sel_prev)

      actions.select_default:replace(function()
        local picker     = action_state.get_current_picker(prompt_bufnr)
        local selections = picker:get_multi_selection()

        if #selections == 0 then
          local entry = action_state.get_selected_entry()
          if entry then selections = { entry } end
        end

        actions.close(prompt_bufnr)

        if #selections == 0 then
          vim.notify("PKMExport: Nothing selected.", vim.log.levels.INFO)
          return
        end

        local selected_paths = {}
        for _, sel in ipairs(selections) do
          table.insert(selected_paths, sel.value)
        end

        vim.schedule(function()
          prompt_dest_and_copy(selected_paths, default_dest)
        end)
      end)

      return true
    end,
  }):find()
end

-- ============================================================================
-- FALLBACK RESULTS FLOAT  (no Telescope)
-- ============================================================================

--- Scrollable floating buffer listing matched files.
--- <CR> exports all; q/<Esc> cancels.
--- @param paths      table
--- @param on_confirm function(paths)
--- @param on_cancel  function()
local function show_result_float(paths, on_confirm, on_cancel)
  local header    = string.format(
    "  %d note%s matched  ·  <CR> export all  ·  q/<Esc> cancel",
    #paths, #paths == 1 and "" or "s")
  local separator = "  " .. string.rep("─", math.max(#header - 2, 10))

  local lines = { header, separator }
  for _, p in ipairs(paths) do
    table.insert(lines, "  • " .. vim.fn.fnamemodify(p, ":t"))
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
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
    title     = ' PKMExport: Matched Notes ',
    title_pos = 'center',
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local ko = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set('n', '<CR>',  function() close(); on_confirm(paths) end, ko)
  vim.keymap.set('n', 'q',     function() close(); on_cancel()       end, ko)
  vim.keymap.set('n', '<Esc>', function() close(); on_cancel()       end, ko)
end

-- ============================================================================
-- ENTRY POINT
-- ============================================================================

--- Launch the full interactive export UI.
--- Step 1: floating filter form.
--- Step 2: Telescope results picker (if available) or scrollable float.
--- Step 3: destination prompt and copy.
function M.interactive_export()
  local config       = require('pkm').config
  local default_dest = utils.join(config.root_path, "exports", os.date("%Y%m%d_%H%M%S"))

  show_filter_form(function(filters)
    local paths = M.collect_files(filters)

    if #paths == 0 then
      vim.notify("PKMExport: No notes matched the given filters.", vim.log.levels.INFO)
      return
    end

    local has_telescope = pcall(require, 'telescope')
    if has_telescope then
      telescope_results_picker(paths, default_dest)
    else
      show_result_float(
        paths,
        function(confirmed)
          vim.schedule(function()
            prompt_dest_and_copy(confirmed, default_dest)
          end)
        end,
        function()
          vim.notify("PKMExport: Cancelled.", vim.log.levels.INFO)
        end
      )
    end
  end)
end

return M
