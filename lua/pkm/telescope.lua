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
--   browse_tags()             → tag list → ripgrep by tag
--   find_notes()              → telescope find_files over PKM root
--   search_notes()            → telescope live_grep over PKM root (requires rg)
--   merge_tags_picker()       → 3-step: pick target, multi-select sources, confirm
-- =============================================================================
local M = {}

local citations = require('pkm.citations')

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
-- SECTION: Tag and note browsing
-- =============================================================================
--- Show all tags in a picker. On select, runs ripgrep for that tag across the
--- PKM root using telescope builtin.grep_string. Requires ripgrep.
function M.browse_tags()
  if not check_ripgrep() then return end

  local t = require_telescope()
  if not t then return end

  local tags = citations.get_all_tags()
  local root = require('pkm').config.root_path

  t.pickers.new({}, {
    prompt_title = "Browse Notes by Tag",
    finder = t.finders.new_table {
      results = tags,
      entry_maker = function(entry)
        return { value = entry, display = entry, ordinal = entry }
      end,
    },
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      t.actions.select_default:replace(function()
        t.actions.close(prompt_bufnr)
        local selection = t.state.get_selected_entry()
        if selection then
          local tag = selection.value
          t.builtin.grep_string({
            prompt_title    = "Notes with tag: " .. tag,
            search          = tag,
            cwd             = root,
            additional_args = function() return { "--hidden" } end,
          })
        end
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
