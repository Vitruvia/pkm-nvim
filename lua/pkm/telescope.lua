-- =============================================================================
-- pkm.telescope — Telescope pickers for notes, tags, citations, and export
-- =============================================================================
-- Dependencies : pkm.citations, telescope.nvim (optional, checked at call time)
-- Consumed by  : pkm.commands
--
-- Telescope availability is checked at call time inside require_telescope(),
-- consistent with the project-wide pattern. The module always loads cleanly;
-- each function notifies and returns early when Telescope is unavailable.
--
-- Public API:
--   insert_citation_picker()  → fuzzy citation picker, inserts on select
--   browse(filter_expr?)         → Browse notes with optional filter expression
--   browse_tags()                → Tag picker → browse pre-filtered to tag:<selected>
--   find_notes()              → telescope find_files over PKM root
--   search_notes()            → telescope live_grep over PKM root (requires rg)
--   merge_tags_picker()       → 3-step: pick target, multi-select sources, confirm
-- =============================================================================
local M = {}

local citations = require('pkm.citations')
local _TYPE_ORDER = { note = 1, agg = 2, bib = 3, journal = 4, scratch = 5, other = 6 }

-- =============================================================================
-- SECTION: Helpers
-- =============================================================================

--- Require Telescope and all sub-modules used by the pickers.
--- Checked at call time — never at module load time. Each caller checks the
--- return value and returns early if nil.
---@return table|nil t { pickers, finders, conf, actions, state, builtin }
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

local function check_ripgrep()
  if vim.fn.executable("rg") == 0 then
    vim.notify("PKM Error: 'rg' (Ripgrep) not found. Please install it.", vim.log.levels.ERROR)
    return false
  end
  return true
end

-- =============================================================================
-- SECTION: Citation picker
-- =============================================================================
--- Fuzzy picker over all citable notes. Inserts citation token at cursor on select.
--- Calls citations.complete_insertion() which also triggers update_references().
function M.insert_citation_picker()
  local t = require_telescope()
  if not t then return end

  local items = citations.get_citable_items_list()

  t.pickers.new({}, {
    prompt_title = "Insert Citation",
    finder = t.finders.new_table {
      results = items,
      entry_maker = function(entry)
        return {
          value   = entry,
          display = entry.display,
          ordinal = entry.display,
        }
      end,
    },
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      t.actions.select_default:replace(function()
        t.actions.close(prompt_bufnr)
        local selection = t.state.get_selected_entry()
        if selection then
          citations.complete_insertion(selection.value)
        end
      end)
      return true
    end,
  }):find()
end

-- =============================================================================
-- SECTION: Note browser
-- =============================================================================

--- Open a picker over all PKM notes, optionally pre-filtered by a filter
--- expression. Empty or nil expr shows all notes. The Telescope prompt applies
--- exact substring narrowing over the pre-filtered set; fzy is not used.
---@param filter_expr string|nil  Filter expression string or nil for all notes
function M.browse(filter_expr)
  local t = require_telescope()
  if not t then return end

  local filter = require('pkm.filter')
  local index  = require('pkm.index')

  local all_entries = index.get_all()
  local entries

  if filter_expr and filter_expr ~= '' then
    local tree, err = filter.parse(filter_expr)
    if not tree then
      vim.notify('[pkm] invalid filter: ' .. err, vim.log.levels.ERROR)
      return
    end
    entries = {}
    for _, e in ipairs(all_entries) do
      if filter.eval(tree, e) then entries[#entries + 1] = e end
    end
  else
    entries = all_entries
  end

  if #entries == 0 then
    vim.notify('[pkm] no notes match', vim.log.levels.INFO)
    return
  end

  -- Sort entries by type then title
  table.sort(entries, function(a, b)
    local ta = _TYPE_ORDER[a.note_type] or 6
    local tb = _TYPE_ORDER[b.note_type] or 6
    if ta ~= tb then return ta < tb end
    return (a.title or ''):lower() < (b.title or ''):lower()
  end)

  local items = {}
  for _, e in ipairs(entries) do
    local prefix = string.format('[%-7s]', e.note_type or 'other')
    items[#items + 1] = {
      path    = e.path,
      display = prefix .. ' ' .. e.title .. '  (' .. e.filename .. ')',
      ordinal = string.format('%05d', #items + 1),
    }
  end

  t.pickers.new({}, {
    prompt_title = filter_expr and ('PKMBrowse: ' .. filter_expr) or 'PKMBrowse',
    finder = t.finders.new_dynamic {
      fn = function(prompt)
        if not prompt or prompt == '' then return items end
        local needle = prompt:lower()
        local out = {}
        for _, item in ipairs(items) do
          if item.display:lower():find(needle, 1, true) then out[#out + 1] = item end
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

--- Open telescope live_grep over the PKM root. Searches note body content.
--- Requires ripgrep. Filters to *.md files only.
function M.search_notes()
  if not check_ripgrep() then return end

  local t = require_telescope()
  if not t then return end

  local root = require('pkm').config.root_path

  if vim.fn.isdirectory(root) == 0 then
    vim.notify("PKM Error: Invalid root path for search: " .. tostring(root), vim.log.levels.ERROR)
    return
  end

  t.builtin.live_grep({
    prompt_title    = "Search Note Content",
    cwd             = root,
    glob_pattern    = "*.md",
    additional_args = function() return { "--hidden", "--no-ignore" } end,
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
