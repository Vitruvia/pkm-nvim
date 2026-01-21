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
  local root = require('pkm.init').config.root_path
  
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
    cwd = require('pkm.init').config.root_path,
    hidden = true,
    no_ignore = true,
  })
end

-- 4. Search Note Content (Live Grep)
function M.search_notes()
  if not check_ripgrep() then return end

  local root = require('pkm.init').config.root_path
  
  if vim.fn.isdirectory(root) == 0 then
     vim.notify("PKM Error: Invalid root path for search: " .. tostring(root), vim.log.levels.ERROR)
     return
  end

  builtin.live_grep({
    prompt_title = "Search Note Content",
    cwd = root,
    glob_pattern = "*.md",
    additional_args = function() 
        return { "--hidden", "--no-ignore", "--fixed-strings" } 
    end
  })
end

return M
