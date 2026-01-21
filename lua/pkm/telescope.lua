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
        citations.complete_insertion(selection.value)
      end)
      return true
    end,
  }):find()
end

-- 2. Browse Tags Picker
function M.browse_tags()
  local tags = citations.get_all_tags()
  
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
        local tag = selection.value
        
        -- Search for the tag in the files
        builtin.grep_string({
          prompt_title = "Notes with tag: " .. tag,
          search = tag, 
          cwd = require('pkm.init').config.root_path,
        })
      end)
      return true
    end,
  }):find()
end

-- 3. Find Note Files (by filename)
function M.find_notes()
  builtin.find_files({
    prompt_title = "Find Notes",
    cwd = require('pkm.init').config.root_path,
    hidden = false,
    find_command = { "find", ".", "-type", "f", "-name", "*.md" } -- Optimization for Linux/WSL
  })
end

-- 4. Search Note Content (Live Grep) - Fixed for <leader>nf
function M.search_notes()
  -- Requires 'ripgrep' to be installed on the system
  builtin.live_grep({
    prompt_title = "Search Note Content",
    cwd = require('pkm.init').config.root_path,
    glob_pattern = "*.md", -- Only search markdown files
  })
end

return M
