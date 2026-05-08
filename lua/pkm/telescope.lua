-- lua/pkm/telescope.lua
local M = {}
local citations = require('pkm.citations')
local has_telescope, telescope = pcall(require, 'telescope')

if not has_telescope then return M end

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local builtin = require('telescope.builtin')

local function check_ripgrep()
  if vim.fn.executable("rg") == 0 then
    vim.notify("PKM Error: 'rg' (Ripgrep) not found. Please install it.", vim.log.levels.ERROR)
    return false
  end
  return true
end

-- 1. Insert Citation Picker
function M.insert_citation_picker()
  local items = citations.get_citable_items_list()
  
  pickers.new({}, {
    prompt_title = "Insert Citation",
    finder = finders.new_table {
      results = items,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.display,
        }
      end
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
            citations.complete_insertion(selection.value)
        end
      end)
      return true
    end,
  }):find()
end

-- 2. Browse Tags Picker
function M.browse_tags()
  if not check_ripgrep() then return end
  
  local tags = citations.get_all_tags()
  local root = require('pkm').config.root_path
  
  pickers.new({}, {
    prompt_title = "Browse Notes by Tag",
    finder = finders.new_table {
      results = tags,
      entry_maker = function(entry) 
          return { value = entry, display = entry, ordinal = entry } 
      end
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
            local tag = selection.value
            builtin.grep_string({
              prompt_title = "Notes with tag: " .. tag,
              search = tag, 
              cwd = root,
              additional_args = function() return { "--hidden" } end
            })
        end
      end)
      return true
    end,
  }):find()
end

-- 3. Find Note Files (by filename)
function M.find_notes()
  builtin.find_files({
    prompt_title = "Find Notes (Filename)",
    cwd = require('pkm').config.root_path,
    hidden = true,
    no_ignore = true,
  })
end

-- 4. Search Note Content (Live Grep)
function M.search_notes()
  if not check_ripgrep() then return end

  local root = require('pkm').config.root_path
  
  if vim.fn.isdirectory(root) == 0 then
     vim.notify("PKM Error: Invalid root path for search: " .. tostring(root), vim.log.levels.ERROR)
     return
  end

  builtin.live_grep({
    prompt_title = "Search Note Content",
    cwd = root,
    glob_pattern = "*.md",
    additional_args = function() 
        return { "--hidden", "--no-ignore" } 
    end
  })
end

-- 5. Merge Tags Picker
-- Step 1: pick TARGET (single select).
-- Step 2: pick SOURCE tags (multi-select with <Tab>).
-- Step 3: confirm and execute.
function M.merge_tags_picker()
  local citations_mod = require('pkm.citations')
  local all_tags = citations_mod.get_all_tags()

  if #all_tags == 0 then
    vim.notify("PKM: No tags found.", vim.log.levels.INFO)
    return
  end

  -- ── Step 1: pick TARGET ────────────────────────────────────────────────
  pickers.new({}, {
    prompt_title = "Merge Tags — Step 1: Pick TARGET tag",
    finder = finders.new_table {
      results = all_tags,
      entry_maker = function(t)
        return { value = t, display = t, ordinal = t }
      end,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local sel = action_state.get_selected_entry()
        if not sel then return end
        local target = sel.value

        local source_candidates = vim.tbl_filter(
          function(t) return t ~= target end, all_tags
        )

        if #source_candidates == 0 then
          vim.notify("PKM: No other tags available to merge.", vim.log.levels.INFO)
          return
        end

        -- ── Step 2: pick SOURCES (multi-select) ──────────────────────────
        vim.schedule(function()
          pickers.new({}, {
            prompt_title = "Merge Tags — Step 2: Sources → '"
              .. target .. "'  (<Tab> multi-select, <CR> confirm)",
            finder = finders.new_table {
              results = source_candidates,
              entry_maker = function(t)
                return { value = t, display = t, ordinal = t }
              end,
            },
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr2, map2)
              -- Standard multi-select binding
              map2('i', '<Tab>', function()
                actions.toggle_selection(prompt_bufnr2)
                actions.move_selection_next(prompt_bufnr2)
              end)
              map2('n', '<Tab>', function()
                actions.toggle_selection(prompt_bufnr2)
                actions.move_selection_next(prompt_bufnr2)
              end)

              actions.select_default:replace(function()
                local picker2  = action_state.get_current_picker(prompt_bufnr2)
                local multi    = picker2:get_multi_selection()
                actions.close(prompt_bufnr2)

                -- Fall back to the highlighted entry if nothing was toggled
                if #multi == 0 then
                  local cur = action_state.get_selected_entry()
                  if cur then multi = { cur } end
                end

                if #multi == 0 then
                  vim.notify("PKM: No source tags selected.", vim.log.levels.INFO)
                  return
                end

                local sources  = vim.tbl_map(function(e) return e.value end, multi)

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
