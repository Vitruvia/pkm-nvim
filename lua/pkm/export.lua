-- =============================================================================
-- pkm.export — Note filtering and copy utility
-- =============================================================================
-- Dependencies : pkm.utils, pkm.filter (lazy), pkm.index (lazy),
--                pkm.yaml (lazy, fallback only), pkm.citations (lazy, deep
--                export only), pkm.init (for config), telescope (optional)
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
--   read_citation_edges(path)  → {cites, cited_by} — identifier lists, all groups
--   collect_deep(seeds, opts?) → string[] — seeds expanded across the citation
--                                graph; per-path budget of cites_depth (2) and
--                                cited_by_depth (0) hops, mixable in any order
--   copy_files(paths, dest)    → (copied, errors) — copy to destination
--   export(filters, dest)      → programmatic no-UI entry point
--   export_direct(label, paths) → export a pre-computed path list, skipping the filter form
--   interactive_export()       → full UI: filter form → picker → copy
--   deep_export()              → full UI: depths → filter form → picker (the
--                                selection is the seed set) → graph walk → copy
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
  local lines = utils.read_lines(path)
  if not lines then return nil, nil, nil end
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
-- CITATION GRAPH
-- ============================================================================

-- The four citable groups every cites/cited_by table carries. Notes written
-- before the grouped structure landed may still hold a flat array instead;
-- read_citation_edges accepts both rather than silently returning no edges.
local CITE_GROUPS = { 'notes', 'bib', 'journal', 'scratch' }

--- Append every identifier found in one cites/cited_by value to out.
--- Accepts the grouped shape ({notes={…}, bib={…}, …}), the legacy flat array,
--- and entries that are bare identifier strings instead of tables.
---@param value any     Frontmatter value for `cites` or `cited_by`
---@param out   string[] Collected identifiers, appended in place
local function gather_identifiers(value, out)
  if type(value) ~= 'table' then return end

  local function take(entry)
    if type(entry) == 'string' then
      if entry ~= '' then out[#out + 1] = entry end
    elseif type(entry) == 'table' and type(entry.identifier) == 'string'
       and entry.identifier ~= '' then
      out[#out + 1] = entry.identifier
    end
  end

  local grouped = false
  for _, group in ipairs(CITE_GROUPS) do
    if type(value[group]) == 'table' then
      grouped = true
      for _, entry in ipairs(value[group]) do take(entry) end
    end
  end

  -- Legacy flat array: only consider it when no group key was present, so a
  -- grouped table never gets scanned twice.
  if not grouped then
    for _, entry in ipairs(value) do take(entry) end
  end
end

--- Read one note's citation edges as identifier lists.
--- Read-only and total: an unreadable file, a file without frontmatter, or a
--- note with no citations all yield empty lists rather than an error.
---@param path string  Absolute path to a note file
---@return {cites: string[], cited_by: string[]}
function M.read_citation_edges(path)
  local edges = { cites = {}, cited_by = {} }

  local fm = get_file_data(path)
  if not fm then return edges end

  gather_identifiers(fm.cites,    edges.cites)
  gather_identifiers(fm.cited_by, edges.cited_by)
  return edges
end

--- Expand a set of seed notes across the citation graph.
---
--- Traversal is a **per-path budget**: both depths are counted from the seeds,
--- and a single path may mix directions — it may spend up to `cites_depth`
--- hops along `cites` and up to `cited_by_depth` hops along `cited_by`, in any
--- order. With the default 2/0 no `cited_by` hop is allowed, so the result is
--- the seeds plus everything they cite, transitively, two hops out.
---
--- Termination: every hop strictly decreases one budget, and a note is only
--- re-expanded when it is reached with a budget the visited one does not
--- dominate, so cycles of any length stop on their first non-improving revisit.
---
--- Pure: reads note files and returns paths; opens no window and changes no
--- state. Identifier resolution goes through `citations.get_citable_items_map()`,
--- called once per run (it scans all three note folders), or through
--- `opts.items_map` when the caller already has one.
---@param seed_paths string[]  Absolute paths to start from
---@param opts table|nil  { cites_depth = 2, cited_by_depth = 0, items_map? }
---@return string[]  Deduplicated paths sorted by basename, seeds included
function M.collect_deep(seed_paths, opts)
  opts = opts or {}
  local cites_depth    = opts.cites_depth    or 2
  local cited_by_depth = opts.cited_by_depth or 0

  local items_map = opts.items_map
    or require('pkm.citations').get_citable_items_map()

  -- identifier → path, from whichever map shape the caller supplied.
  local id_to_path = {}
  for id, data in pairs(items_map) do
    local path = type(data) == 'table' and data.path or data
    if type(path) == 'string' then id_to_path[id] = path end
  end

  local best    = {}   -- path → { cites, cited_by } best remaining budget seen
  local found   = {}   -- path → true, everything reached (seeds included)
  local queue   = {}
  local head    = 1

  --- Enqueue path when it arrives with a budget not already dominated.
  local function push(path, cites_left, cited_by_left)
    found[path] = true
    local seen = best[path]
    if seen and seen.cites >= cites_left and seen.cited_by >= cited_by_left then
      return
    end
    best[path] = {
      cites    = seen and math.max(seen.cites,    cites_left)    or cites_left,
      cited_by = seen and math.max(seen.cited_by, cited_by_left) or cited_by_left,
    }
    queue[#queue + 1] = { path = path, cites = cites_left, cited_by = cited_by_left }
  end

  for _, path in ipairs(seed_paths or {}) do
    push(path, cites_depth, cited_by_depth)
  end

  while head <= #queue do
    local node = queue[head]
    head = head + 1

    if node.cites > 0 or node.cited_by > 0 then
      local edges = M.read_citation_edges(node.path)

      if node.cites > 0 then
        for _, id in ipairs(edges.cites) do
          local target = id_to_path[id]
          if target then push(target, node.cites - 1, node.cited_by) end
        end
      end
      if node.cited_by > 0 then
        for _, id in ipairs(edges.cited_by) do
          local target = id_to_path[id]
          if target then push(target, node.cites, node.cited_by - 1) end
        end
      end
    end
  end

  local paths, keys = {}, {}
  for path in pairs(found) do
    paths[#paths + 1] = path
    keys[path] = vim.fn.fnamemodify(path, ':t')
  end
  table.sort(paths, function(a, b) return keys[a] < keys[b] end)
  return paths
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
-- ENTRY POINTS
-- ============================================================================

--- Show the note picker over paths and copy whatever is confirmed.
--- Selection itself lives in `pkm.picker` since v1.8.0 Ph2, so every set
--- operation in the plugin shares one gesture.
---@param paths        string[]
---@param default_dest string
---@param title        string|nil    Picker label; nil uses 'PKMExport'
---@param on_confirm   function|nil  Defaults to the destination prompt and copy
local function select_notes(paths, default_dest, title, on_confirm)
  require('pkm.picker').select(paths, {
    title     = title or 'PKMExport',
    hint      = 'export listed',
    on_cancel = function() vim.notify('PKMExport: Cancelled.', vim.log.levels.INFO) end,
  }, on_confirm or function(confirmed)
    prompt_dest_and_copy(confirmed, default_dest)
  end)
end

--- Launch the full interactive export UI.
--- Step 1: floating filter form.
--- Step 2: note picker (Telescope or float).
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

    select_notes(paths, default_dest, nil, function(confirmed)
      prompt_dest_and_copy(confirmed, default_dest)
    end)
  end)
end

--- Prompt for one traversal depth, accepting blank as the default.
--- Cancelling (Esc) aborts the flow silently; a non-integer or negative value
--- aborts with a warning rather than guessing what was meant.
---@param label   string   Shown before the default, e.g. "Depth along cites"
---@param default integer
---@param on_ok   function(depth: integer)
local function prompt_depth(label, default, on_ok)
  vim.ui.input({ prompt = string.format('%s [%d]: ', label, default) }, function(input)
    if input == nil then return end
    local text = vim.trim(input)
    if text == '' then
      vim.schedule(function() on_ok(default) end)
      return
    end
    local n = tonumber(text)
    if not n or n < 0 or n ~= math.floor(n) then
      vim.notify(
        'PKMExport: depth must be a non-negative whole number — cancelled',
        vim.log.levels.WARN)
      return
    end
    vim.schedule(function() on_ok(n) end)
  end)
end

--- Launch the deep-export UI. Identical to the simple flow up to the picker —
--- filter form, then pick the notes you want — except that the notes selected
--- there are **seeds**: the citation walk runs on the selection, and what it
--- pulls in is exported with it.
---
--- Selecting the seeds after the filter, rather than treating every filter
--- match as a seed, is what makes "export this note and what it links to"
--- expressible: filter loosely, mark the one note you meant, expand from it.
function M.deep_export()
  local config       = require('pkm').config
  local default_dest = utils.join(config.root_path, 'exports', os.date('%Y%m%d_%H%M%S'))

  prompt_depth('Depth along cites', 2, function(cites_depth)
    prompt_depth('Depth along cited_by', 1, function(cited_by_depth)
      show_filter_form(function(filters)
        local candidates = M.collect_files(filters)
        if #candidates == 0 then
          vim.notify('PKMExport: No notes matched the given filters.', vim.log.levels.INFO)
          return
        end

        local title = string.format('PKMExport deep (cites %d, cited_by %d): pick seeds',
          cites_depth, cited_by_depth)

        select_notes(candidates, default_dest, title, function(seeds)
          local paths = M.collect_deep(seeds, {
            cites_depth    = cites_depth,
            cited_by_depth = cited_by_depth,
          })

          vim.notify(string.format(
            'PKMExport: %d seed%s → %d note%s after following citations',
            #seeds,  #seeds  == 1 and '' or 's',
            #paths,  #paths  == 1 and '' or 's'),
            vim.log.levels.INFO)

          prompt_dest_and_copy(paths, default_dest)
        end)
      end)
    end)
  end)
end

--- Export a pre-computed path list, skipping the filter form.
--- Opens the results picker directly, then prompts for destination.
--- Used by :PKMExportView and context-aware export from the sidebar.
---@param label string   Display label shown in the picker title
---@param paths string[] Pre-computed path list
function M.export_direct(label, paths)
  if #paths == 0 then
    vim.notify('PKMExport: no notes to export', vim.log.levels.INFO)
    return
  end

  local cfg          = require('pkm').config
  local default_dest = utils.join(cfg.root_path, 'exports', os.date('%Y%m%d_%H%M%S'))

  select_notes(paths, default_dest, label, function(confirmed)
    prompt_dest_and_copy(confirmed, default_dest)
  end)
end

return M
