-- lua/pkm/export.lua
--
-- Export utility: select notes and copy them to a folder for external use.
-- READ-ONLY — never modifies any note file.
--
-- Primary UI  : Telescope picker (fuzzy search · Tab multi-select · preview)
-- Fallback UI : Sequential prompts + floating result buffer
--
-- Filter semantics (fallback path only; Telescope filtering is interactive):
--   tags_any  OR  — note has at least one of the given tags
--   tags_all  AND — note has every one of the given tags
--   status    OR  — note status equals any of the given values
--   title         case-insensitive substring match on frontmatter title
--
-- Dependencies:
--   require('pkm.yaml')   — parse_frontmatter only, loaded lazily
--   require('pkm').config — root_path and folders, loaded lazily
--   require('telescope')  — optional; fallback activated when absent

local M = {}

local path_sep = package.config:sub(1, 1)

-- ============================================================================
-- SHARED UTILITIES
-- ============================================================================

local function join_path(...)
  return table.concat({ ... }, path_sep)
end

--- Pure-Lua binary-safe file copy. No system calls; works on Windows and WSL.
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

--- Parse frontmatter from a file path. Returns nil if unreadable or absent.
--- @param path string
--- @return table|nil frontmatter
local function get_frontmatter(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then return nil end
  local fm, _ = require('pkm.yaml').parse_frontmatter(lines)
  return fm
end

--- Split a comma-separated string into trimmed, non-empty tokens.
--- @param str string
--- @return table
local function split_csv(str)
  local result = {}
  for item in str:gmatch("[^,]+") do
    local trimmed = item:match("^%s*(.-)%s*$")
    if trimmed ~= "" then table.insert(result, trimmed) end
  end
  return result
end

-- ============================================================================
-- FILTER ENGINE   (used by fallback; Telescope does live interactive filtering)
-- ============================================================================

--- Normalise frontmatter tags to a flat list of lowercase strings.
--- @param raw any
--- @return table
local function normalise_tags(raw)
  if type(raw) == "string" then raw = { raw } end
  if type(raw) ~= "table" then return {} end
  local out = {}
  for _, t in ipairs(raw) do
    if type(t) == "string" then table.insert(out, t:lower()) end
  end
  return out
end

--- Test whether a note file satisfies all active filters.
---
--- @param path    string  Absolute path to a .md file
--- @param filters table   Filter spec; all fields optional / nil = inactive
--- @return boolean
function M.match_file(path, filters)
  local fm = get_frontmatter(path)
  if not fm then return false end

  local note_tags = normalise_tags(fm.tags)

  -- tags_any: OR — at least one filter tag present in note
  if filters.tags_any and #filters.tags_any > 0 then
    local found = false
    for _, wanted in ipairs(filters.tags_any) do
      local wl = wanted:lower()
      for _, actual in ipairs(note_tags) do
        if actual == wl then found = true; break end
      end
      if found then break end
    end
    if not found then return false end
  end

  -- tags_all: AND — every filter tag must be present
  if filters.tags_all and #filters.tags_all > 0 then
    for _, wanted in ipairs(filters.tags_all) do
      local wl    = wanted:lower()
      local found = false
      for _, actual in ipairs(note_tags) do
        if actual == wl then found = true; break end
      end
      if not found then return false end
    end
  end

  -- status: OR
  if filters.status and #filters.status > 0 then
    local note_status = type(fm.status) == "string" and fm.status:lower() or ""
    local found       = false
    for _, s in ipairs(filters.status) do
      if note_status == s:lower() then found = true; break end
    end
    if not found then return false end
  end

  -- title: case-insensitive substring
  if filters.title and filters.title ~= "" then
    local note_title = type(fm.title) == "string" and fm.title:lower() or ""
    if not note_title:find(filters.title:lower(), 1, true) then return false end
  end

  return true
end

--- Collect all .md files from PKM folders that satisfy filters.
--- @param filters table
--- @return table  sorted list of absolute paths
function M.collect_files(filters)
  local config  = require('pkm').config
  local matched = {}

  for _, folder in pairs(config.folders) do
    local dir = join_path(config.root_path, folder)
    if vim.fn.isdirectory(dir) == 1 then
      local files = vim.fn.glob(dir .. path_sep .. "*.md", false, true)
      for _, filepath in ipairs(files) do
        if M.match_file(filepath, filters) then
          table.insert(matched, filepath)
        end
      end
    end
  end

  table.sort(matched, function(a, b)
    return vim.fn.fnamemodify(a, ":t") < vim.fn.fnamemodify(b, ":t")
  end)
  return matched
end

-- ============================================================================
-- COPY ENGINE   (shared by both UI paths)
-- ============================================================================

--- Copy a list of absolute paths into dest. Reports results via vim.notify.
--- @param paths table   List of source paths
--- @param dest  string  Destination directory (created if absent)
--- @return number copied
--- @return number errors
function M.copy_files(paths, dest)
  if not ensure_dir(dest) then
    vim.notify("PKMExport: Cannot create destination: " .. dest, vim.log.levels.ERROR)
    return 0, #paths
  end

  local copied, errors = 0, 0
  for _, src in ipairs(paths) do
    local filename = vim.fn.fnamemodify(src, ":t")
    local ok, err  = copy_file(src, join_path(dest, filename))
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

--- Programmatic entry point: collect via filter spec then copy.
--- Example:
---   require('pkm.export').export(
---     { tags_any = {"math"}, tags_all = {"proof", "analysis"} },
---     "/tmp/llm-context"
---   )
--- @param filters table
--- @param dest    string
function M.export(filters, dest)
  local paths = M.collect_files(filters)
  if #paths == 0 then
    vim.notify("PKMExport: No notes matched.", vim.log.levels.INFO)
    return
  end
  M.copy_files(paths, dest)
end

-- ============================================================================
-- TELESCOPE UI PATH
-- ============================================================================

--- Build the ordinal string for fuzzy matching.
---
--- Format: "<basename> <title> <tag1> <tag2> ... <status>"  (all lowercase)
---
--- Telescope's fzy sorter matches the query as a subsequence against this
--- string. Typing multiple space-separated words (e.g. "math proof") narrows
--- results because each character of the full query must appear in order —
--- effectively an AND of all typed characters across all metadata fields.
---
--- @param path string
--- @param fm   table
--- @return string
local function build_ordinal(path, fm)
  local parts = { vim.fn.fnamemodify(path, ":t:r"):lower() }
  if type(fm.title) == "string" then
    table.insert(parts, fm.title:lower())
  end
  if type(fm.tags) == "table" then
    for _, t in ipairs(fm.tags) do
      if type(t) == "string" then table.insert(parts, t:lower()) end
    end
  end
  if type(fm.status) == "string" then
    table.insert(parts, fm.status:lower())
  end
  return table.concat(parts, " ")
end

--- Build the display string shown in the Telescope picker row.
--- Format: "<filename>  [tag1, tag2]  status"
--- @param path string
--- @param fm   table
--- @return string
local function build_display(path, fm)
  local name = vim.fn.fnamemodify(path, ":t")

  local tags = {}
  if type(fm.tags) == "table" then
    for _, t in ipairs(fm.tags) do
      if type(t) == "string" then table.insert(tags, t) end
    end
  end

  local tag_str    = #tags > 0 and ("  [" .. table.concat(tags, ", ") .. "]") or ""
  local status_str = type(fm.status) == "string" and ("  " .. fm.status) or ""
  return name .. tag_str .. status_str
end

--- Prompt for destination and copy. Called after Telescope closes so the
--- input prompt appears cleanly without a lingering picker window.
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

--- Open a Telescope picker over all PKM notes.
---
--- Navigation:
---   Type to fuzzy-filter  (filename · title · tags · status all searched)
---   <Tab>   toggle selection on current entry and move to next
---   <S-Tab> toggle selection on current entry and move to previous
---   <CR>    confirm the selection (or current entry if nothing was Tab-selected)
---   <Esc>   / <C-c>  cancel
local function telescope_export()
  -- Checked at call time to avoid Lazy.nvim deferred-load issues.
  local ok_tel = pcall(require, 'telescope')
  if not ok_tel then
    vim.notify("PKMExport: Telescope not available.", vim.log.levels.ERROR)
    return
  end

  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local conf         = require('telescope.config').values
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers   = require('telescope.previewers')
  local config       = require('pkm').config

  -- Collect every .md file from all PKM folders.
  local entries = {}
  for _, folder in pairs(config.folders) do
    local dir = join_path(config.root_path, folder)
    if vim.fn.isdirectory(dir) == 1 then
      local files = vim.fn.glob(dir .. path_sep .. "*.md", false, true)
      for _, path in ipairs(files) do
        local fm = get_frontmatter(path) or {}
        table.insert(entries, {
          path    = path,
          display = build_display(path, fm),
          ordinal = build_ordinal(path, fm),
        })
      end
    end
  end

  if #entries == 0 then
    vim.notify("PKMExport: No notes found.", vim.log.levels.INFO)
    return
  end

  table.sort(entries, function(a, b) return a.display < b.display end)

  local default_dest = join_path(config.root_path, "exports", os.date("%Y%m%d_%H%M%S"))

  pickers.new({}, {
    prompt_title = "PKMExport  ·  fuzzy search  ·  <Tab> select  ·  <CR> confirm",

    finder = finders.new_table {
      results = entries,
      entry_maker = function(entry)
        return {
          -- `value` is what get_multi_selection() returns per entry.
          value   = entry.path,
          display = entry.display,
          ordinal = entry.ordinal,
          -- `path` is required by vim_buffer_cat previewer.
          path    = entry.path,
        }
      end,
    },

    sorter    = conf.generic_sorter({}),
    previewer = previewers.vim_buffer_cat.new({}),

    attach_mappings = function(prompt_bufnr, map)
      -- Toggle selection and move cursor.
      local sel_next = actions.toggle_selection + actions.move_selection_next
      local sel_prev = actions.toggle_selection + actions.move_selection_previous
      map("i", "<Tab>",   sel_next)
      map("n", "<Tab>",   sel_next)
      map("i", "<S-Tab>", sel_prev)
      map("n", "<S-Tab>", sel_prev)

      -- <CR>: finalise selection, close picker, prompt for destination.
      actions.select_default:replace(function()
        local picker     = action_state.get_current_picker(prompt_bufnr)
        local selections = picker:get_multi_selection()

        -- If the user pressed <CR> without Tab-selecting, treat the currently
        -- highlighted entry as the sole selection.
        if #selections == 0 then
          local entry = action_state.get_selected_entry()
          if entry then selections = { entry } end
        end

        actions.close(prompt_bufnr)

        if #selections == 0 then
          vim.notify("PKMExport: Nothing selected.", vim.log.levels.INFO)
          return
        end

        local paths = {}
        for _, sel in ipairs(selections) do
          -- sel.value was set to the file path in entry_maker.
          table.insert(paths, sel.value)
        end

        -- Defer one tick so Telescope's window fully closes before
        -- vim.ui.input opens; prevents rendering conflicts.
        vim.schedule(function()
          prompt_dest_and_copy(paths, default_dest)
        end)
      end)

      return true
    end,
  }):find()
end

-- ============================================================================
-- FALLBACK UI PATH   (no Telescope)
-- ============================================================================

--- Open a floating, scrollable, read-only buffer listing matched files.
--- <CR> confirms and proceeds; q / <Esc> cancels.
--- @param paths      table
--- @param on_confirm function(paths)
--- @param on_cancel  function()
local function show_result_buffer(paths, on_confirm, on_cancel)
  local header    = string.format(
    "  %d note%s matched  ·  <CR> confirm  ·  q/<Esc> cancel",
    #paths, #paths == 1 and "" or "s")
  local separator = "  " .. string.rep("─", #header - 2)

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

--- Sequential prompt chain for the fallback (no-Telescope) path.
local function fallback_export()
  local config       = require('pkm').config
  local default_dest = join_path(config.root_path, "exports", os.date("%Y%m%d_%H%M%S"))

  local function trim(s) return s and s:match("^%s*(.-)%s*$") or "" end

  vim.ui.input(
    { prompt = "Tags ANY (OR, comma-separated, empty = skip): " },
    function(v1)
      if v1 == nil then return end
      local tags_any = split_csv(trim(v1))

      vim.ui.input(
        { prompt = "Tags ALL (AND, comma-separated, empty = skip): " },
        function(v2)
          if v2 == nil then return end
          local tags_all = split_csv(trim(v2))

          vim.ui.input(
            { prompt = "Status (OR, comma-separated, empty = skip): " },
            function(v3)
              if v3 == nil then return end
              local status = split_csv(trim(v3))

              vim.ui.input(
                { prompt = "Title contains (substring, empty = skip): " },
                function(v4)
                  if v4 == nil then return end
                  local title = trim(v4)

                  local filters = {
                    tags_any = #tags_any > 0 and tags_any or nil,
                    tags_all = #tags_all > 0 and tags_all or nil,
                    status   = #status   > 0 and status   or nil,
                    title    = title ~= ""   and title    or nil,
                  }

                  local has_filter = filters.tags_any or filters.tags_all
                                  or filters.status   or filters.title
                  if not has_filter then
                    vim.notify(
                      "PKMExport: No filters specified — will match all notes.",
                      vim.log.levels.WARN
                    )
                  end

                  local paths = M.collect_files(filters)
                  if #paths == 0 then
                    vim.notify("PKMExport: No notes matched.", vim.log.levels.INFO)
                    return
                  end

                  show_result_buffer(
                    paths,
                    function(confirmed_paths)
                      vim.ui.input(
                        { prompt  = string.format(
                            "Export %d note%s to: ",
                            #confirmed_paths, #confirmed_paths == 1 and "" or "s"),
                          default = default_dest },
                        function(dest)
                          if not dest or dest:match("^%s*$") then
                            vim.notify("PKMExport: Cancelled.", vim.log.levels.INFO)
                            return
                          end
                          M.copy_files(confirmed_paths, dest)
                        end
                      )
                    end,
                    function()
                      vim.notify("PKMExport: Cancelled.", vim.log.levels.INFO)
                    end
                  )
                end
              )
            end
          )
        end
      )
    end
  )
end

-- ============================================================================
-- ENTRY POINT
-- ============================================================================

--- Launch the export UI.
--- Uses Telescope if available at call time; falls back to prompt chain.
function M.interactive_export()
  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    telescope_export()
  else
    fallback_export()
  end
end

return M
