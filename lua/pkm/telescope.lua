-- =============================================================================
-- pkm.telescope — Telescope pickers for notes, tags, citations, and export
-- =============================================================================
-- Dependencies : pkm.citations, pkm.filter (lazy), pkm.index (lazy),
--                pkm.views (lazy), telescope.nvim (optional, checked at call time)
--
-- Telescope availability is checked at call time inside require_telescope(),
-- consistent with the project-wide pattern. The module always loads cleanly;
-- each function notifies and returns early when Telescope is unavailable.
--
-- Public API:
--   insert_citation_picker()  → context-aware citation picker
--   browse(filter_expr?)      → live filter-as-you-type note browser
--   browse_tags()             → tag picker → browse pre-seeded to tag:<x>
--   browse_recent(n?)         → n most-recently-modified notes (mtime order; live-filterable)
--   browse_paths(title, paths) → scoped live browser over a pre-computed path list
--   find_notes()              → telescope find_files over PKM root
--   merge_tags_picker()       → 3-step tag merge picker
-- =============================================================================
local M = {}

local citations = require('pkm.citations')
local utils = require('pkm.utils')
local _TYPE_ORDER = { note = 1, agg = 2, bib = 3, journal = 4, scratch = 5, other = 6 }

-- =============================================================================
-- SECTION: Helpers
-- =============================================================================

local function type_prefix(note_type)
  local label = note_type or 'other'
  local width = 7
  local pad   = width - #label
  local lpad  = math.floor(pad / 2) + 1
  local rpad  = math.ceil(pad  / 2) + 1
  return '[' .. string.rep(' ', lpad) .. label .. string.rep(' ', rpad) .. ']'
end

--- Require Telescope and all sub-modules used by the pickers.
--- Checked at call time — never at module load time. Each caller checks the
--- return value and returns early if nil.
---@return table|nil t { pickers, finders, sorters, conf, actions, state, builtin }
local function require_telescope()
  local ok = pcall(require, 'telescope')
  if not ok then
    vim.notify("PKM: Telescope is required for this picker.", vim.log.levels.WARN)
    return nil
  end
  return {
    pickers = require('telescope.pickers'),
    finders = require('telescope.finders'),
    sorters = require('telescope.sorters'),
    conf    = require('telescope.config').values,
    actions = require('telescope.actions'),
    state   = require('telescope.actions.state'),
    builtin = require('telescope.builtin'),
  }
end

--- Core live filter-as-you-type picker used by browse() and browse_paths().
--- Items are sorted by type then title at open time; the fn re-evaluates the
--- prompt as a filter.lua expression on every keystroke. Falls back to an
--- any-predicate when the expression is incomplete (e.g. mid-typing "AND").
---@param title   string    Picker prompt title
---@param entries table[]   Index entry array; each entry has path, filename, title, tags, body, note_type
---@param seed    string|nil  Optional expression to pre-populate the prompt
---@param presorted boolean|nil  When true, skip the internal type/title sort
local function live_picker(title, entries, seed, presorted)
  local t = require_telescope()
  if not t then return end
  local filter = require('pkm.filter')

  local sorted = {}
  for _, e in ipairs(entries) do sorted[#sorted + 1] = e end
  if not presorted then
    table.sort(sorted, function(a, b)
      local ta = _TYPE_ORDER[a.note_type] or 6
      local tb = _TYPE_ORDER[b.note_type] or 6
      if ta ~= tb then return ta < tb end
      return (a.title or ''):lower() < (b.title or ''):lower()
    end)
  end

  local all_items = {}
  for i, e in ipairs(sorted) do
    all_items[i] = {
      entry   = e,
      path    = e.path,
      display = type_prefix(e.note_type) .. ' ' .. e.title .. '  (' .. e.filename .. ')',
      ordinal = string.format('%05d', i),
    }
  end

  t.pickers.new({
    default_text     = seed or '',
    sorting_strategy = 'ascending',
    layout_config    = { prompt_position = 'top' },
  }, {
    prompt_title = title,
    finder = t.finders.new_dynamic {
      fn = function(prompt)
        if not prompt or prompt == '' then return all_items end
        -- Parse the prompt; fall back to a bare any-predicate when incomplete
        -- (e.g. mid-typing "AND" without a right operand).
        local tree, _ = filter.parse(prompt)
        if not tree then
          tree = { type = 'PRED', field = 'any', value = prompt }
        end
        local out = {}
        for _, item in ipairs(all_items) do
          if filter.eval(tree, item.entry) then out[#out + 1] = item end
        end
        return out
      end,
      entry_maker = function(item)
        return { value = item.path, display = item.display, ordinal = item.ordinal }
      end,
    },
    sorter    = t.sorters.empty(),
    previewer = t.conf.file_previewer({}),
    attach_mappings = function(prompt_bufnr)
      t.actions.select_default:replace(function()
        t.actions.close(prompt_bufnr)
        local sel = t.state.get_selected_entry()
        if sel then vim.cmd('edit ' .. vim.fn.fnameescape(sel.value)) end
      end)
      return true
    end,
  }):find()
end

-- =============================================================================
-- SECTION: Citation picker
-- =============================================================================

--- Compute a relevance score for one citable item.
--- +2 if the item's path is in view_paths; +1 per tag shared with cur_tags.
---@param item      table   Citable item from get_citable_items_list()
---@param cur_tags  table   Current note's tags as a set (tag → true)
---@param view_paths table  Active view paths as a set (normalized path → true)
---@return integer score
---@return boolean in_view
local function score_item(item, cur_tags, view_paths)
  local norm_path = utils.normalize(item.path)
  local in_view   = view_paths[norm_path] == true
  local score     = in_view and 2 or 0

  local entry = require('pkm.index').get(item.path)
  if entry and entry.tags then
    for _, tag in ipairs(entry.tags) do
      if cur_tags[tag] then score = score + 1 end
    end
  end

  return score, in_view
end

--- Context-aware fuzzy picker over all citable notes.
--- Items are pre-sorted by relevance (view membership + shared tags).
--- '~ ' prefix marks contextually relevant items; '  ' prefix marks others.
--- <C-v> toggles between full list and active-view-only list when a view
--- is active. Calls citations.complete_insertion() on select.
function M.insert_citation_picker()
  local t = require_telescope()
  if not t then return end

  local citations_mod = require('pkm.citations')
  local index         = require('pkm.index')
  local views         = require('pkm.views')

  local raw_items = citations_mod.get_citable_items_list()
  if #raw_items == 0 then
    vim.notify('[pkm] no citable notes found', vim.log.levels.INFO)
    return
  end

  -- Build scoring context
  local cur_path  = vim.fn.expand('%:p')
  local cur_entry = index.get(cur_path)
  local cur_tags  = {}
  if cur_entry and cur_entry.tags then
    for _, tag in ipairs(cur_entry.tags) do cur_tags[tag] = true end
  end

  local view_name  = views.get_last_view()
  local view_paths = {}
  if view_name then
    for _, p in ipairs(views.match_all(view_name)) do
      view_paths[utils.normalize(p)] = true
    end
  end

  -- Score, annotate, sort
  for _, item in ipairs(raw_items) do
    local s, iv  = score_item(item, cur_tags, view_paths)
    item.score   = s
    item.in_view = iv
  end
  table.sort(raw_items, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.display < b.display
  end)

  -- Build entry tables
  local all_entries  = {}
  local view_entries = {}
  for _, item in ipairs(raw_items) do
    local prefix = item.score > 0 and '~ ' or '  '
    local e = {
      value   = item,
      display = prefix .. item.display,
      ordinal = prefix .. item.display,
    }
    all_entries[#all_entries + 1] = e
    if item.in_view then view_entries[#view_entries + 1] = e end
  end

  local has_view       = view_name ~= nil and #view_entries > 0
  local show_view_only = false  -- mutable toggle state

  local title = has_view
    and ('Insert Citation  ~ = contextual  <C-v> view: ' .. view_name)
    or  'Insert Citation  ~ = contextual'

  t.pickers.new({}, {
    prompt_title = title,
    finder = t.finders.new_table {
      results = all_entries,
      entry_maker = function(e) return e end,
    },
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      t.actions.select_default:replace(function()
        t.actions.close(prompt_bufnr)
        local sel = t.state.get_selected_entry()
        if sel then citations_mod.complete_insertion(sel.value) end
      end)

      if has_view then
        local function do_toggle()
          show_view_only = not show_view_only
          local new_source = show_view_only and view_entries or all_entries
          local cur_picker = t.state.get_current_picker(prompt_bufnr)
          cur_picker:refresh(
            t.finders.new_table {
              results      = new_source,
              entry_maker  = function(e) return e end,
            },
            { reset_prompt = false }
          )
          vim.notify(
            show_view_only
              and ('[pkm] citations: ' .. view_name .. ' only')
              or  '[pkm] citations: all notes',
            vim.log.levels.INFO
          )
        end
        map('i', '<C-v>', do_toggle)
        map('n', '<C-v>', do_toggle)
      end

      return true
    end,
  }):find()
end

-- =============================================================================
-- SECTION: Note browser
-- =============================================================================

--- Open the live filter-as-you-type note browser.
--- The prompt is evaluated by filter.lua on each keystroke. Bare text matches
--- any field (title, body, filename, tags); prefixed expressions apply
--- structured filters. filter_expr, when provided, pre-seeds the prompt.
---@param filter_expr string|nil  Optional seed expression (e.g. from :PKMBrowse tag:x)
function M.browse(filter_expr)
  local index = require('pkm.index')
  live_picker('PKMBrowse', index.get_all(), filter_expr)
end

--- Scoped live browser over a pre-computed path list.
--- Uses the same live filter engine as M.browse, restricted to the given paths.
--- Called by the sidebar '/' keymap and the views-tree <C-f> keymap.
---@param title  string
---@param paths  string[]
function M.browse_paths(title, paths)
  local index = require('pkm.index')
  if #paths == 0 then
    vim.notify('[pkm] no notes to search', vim.log.levels.INFO)
    return
  end
  local entries = {}
  for _, path in ipairs(paths) do
    local e = index.get(path)
    if e then entries[#entries + 1] = e end
  end
  if #entries == 0 then
    vim.notify('[pkm] no indexed notes in selection', vim.log.levels.INFO)
    return
  end
  live_picker(title, entries, nil)
end

--- Show the n most recently modified notes, newest first.
--- The live filter bar is still available for narrowing.
--- presorted=true preserves mtime order; no type/title re-sort.
---@param n integer|nil  Max results; defaults to 20
function M.browse_recent(n)
  n = tonumber(n) or 20
  local index = require('pkm.index')
  local entries = index.get_all()
  table.sort(entries, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
  if n > 0 and #entries > n then
    local sliced = {}
    for i = 1, n do sliced[i] = entries[i] end
    entries = sliced
  end
  live_picker(string.format('Recent (%d)', #entries), entries, nil, true)
end

--- Tag picker. On selection, opens PKMBrowse pre-filtered to tag:<selected>.
--- No longer uses ripgrep; tag list is sourced from the citation index.
function M.browse_tags()
  local t = require_telescope()
  if not t then return end

  local tags = citations.get_all_tags()

  if #tags == 0 then
    vim.notify('[pkm] no tags found', vim.log.levels.INFO)
    return
  end

  t.pickers.new({}, {
    prompt_title = 'Browse by Tag',
    finder = t.finders.new_table {
      results = tags,
      entry_maker = function(tag)
        return { value = tag, display = tag, ordinal = tag }
      end,
    },
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      t.actions.select_default:replace(function()
        t.actions.close(prompt_bufnr)
        local sel = t.state.get_selected_entry()
        if sel then M.browse('tag:' .. sel.value) end
      end)
      return true
    end,
  }):find()
end

--- Open telescope find_files over the PKM root. Searches by filename only.
function M.find_notes()
  local t = require_telescope()
  if not t then return end

  t.builtin.find_files({
    prompt_title = "Find Notes (Filename)",
    cwd          = require('pkm').config.root_path,
    hidden       = true,
    no_ignore    = true,
  })
end

-- =============================================================================
-- SECTION: Tag merging
-- =============================================================================
--- Three-step tag merge UI:
---   Step 1 — pick TARGET tag (single select)
---   Step 2 — pick SOURCE tags (multi-select with Tab)
---   Step 3 — confirm via vim.fn.confirm, then call citations.merge_tags()
function M.merge_tags_picker()
  local t = require_telescope()
  if not t then return end

  local citations_mod = require('pkm.citations')
  local all_tags      = citations_mod.get_all_tags()

  if #all_tags == 0 then
    vim.notify("PKM: No tags found.", vim.log.levels.INFO)
    return
  end

  -- ── Step 1: pick TARGET ────────────────────────────────────────────────
  t.pickers.new({}, {
    prompt_title = "Merge Tags — Step 1: Pick TARGET tag",
    finder = t.finders.new_table {
      results = all_tags,
      entry_maker = function(tag)
        return { value = tag, display = tag, ordinal = tag }
      end,
    },
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      t.actions.select_default:replace(function()
        t.actions.close(prompt_bufnr)
        local sel = t.state.get_selected_entry()
        if not sel then return end
        local target = sel.value

        local source_candidates = vim.tbl_filter(
          function(tag) return tag ~= target end, all_tags
        )

        if #source_candidates == 0 then
          vim.notify("PKM: No other tags available to merge.", vim.log.levels.INFO)
          return
        end

        -- ── Step 2: pick SOURCES (multi-select) ──────────────────────────
        vim.schedule(function()
          t.pickers.new({}, {
            prompt_title = "Merge Tags — Step 2: Sources → '"
              .. target .. "'  (<Tab> multi-select, <CR> confirm)",
            finder = t.finders.new_table {
              results = source_candidates,
              entry_maker = function(tag)
                return { value = tag, display = tag, ordinal = tag }
              end,
            },
            sorter = t.conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr2, map2)
              map2('i', '<Tab>', function()
                t.actions.toggle_selection(prompt_bufnr2)
                t.actions.move_selection_next(prompt_bufnr2)
              end)
              map2('n', '<Tab>', function()
                t.actions.toggle_selection(prompt_bufnr2)
                t.actions.move_selection_next(prompt_bufnr2)
              end)

              t.actions.select_default:replace(function()
                local picker2 = t.state.get_current_picker(prompt_bufnr2)
                local multi   = picker2:get_multi_selection()
                t.actions.close(prompt_bufnr2)

                if #multi == 0 then
                  local cur = t.state.get_selected_entry()
                  if cur then multi = { cur } end
                end

                if #multi == 0 then
                  vim.notify("PKM: No source tags selected.", vim.log.levels.INFO)
                  return
                end

                local sources = vim.tbl_map(function(e) return e.value end, multi)

                -- ── Step 3: confirm ──────────────────────────────────────
                vim.schedule(function()
                  local src_str = table.concat(sources, ", ")
                  local choice  = vim.fn.confirm(
                    string.format(
                      "Merge [%s]\n→ '%s'\n\nThis will rewrite all affected notes. Proceed?",
                      src_str, target
                    ),
                    "&Yes\n&No", 2
                  )
                  if choice ~= 1 then
                    vim.notify("PKM: Tag merge cancelled.", vim.log.levels.INFO)
                    return
                  end

                  local count = citations_mod.merge_tags(sources, target)
                  vim.notify(
                    string.format(
                      "PKM: Merged [%s] → '%s' in %d file(s).",
                      src_str, target, count
                    ),
                    vim.log.levels.INFO
                  )
                end)
              end)

              return true
            end,
          }):find()
        end)
      end)
      return true
    end,
  }):find()
end

return M
