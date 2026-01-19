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

-- ... Insert Citation Picker (Keep existing code) ...
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
            local item = selection.value
            -- Use the citations module to insert
            require('pkm.citations').complete_insertion(item)
        end
      end)
      return true
    end,
  }):find()
end

function M.browse_tags()
  local tags = citations.get_all_tags()
  
  pickers.new({}, {
    prompt_title = "Browse Tags",
    finder = finders.new_table {
      results = tags,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
            local tag = selection[1]
            -- Fix: Use explicit string search to avoid regex errors
            builtin.grep_string({
              prompt_title = "Tag: " .. tag,
              search = tag,
              use_regex = false, 
              cwd = require('pkm.init').config.root_path
            })
        end
      end)
      return true
    end,
  }):find()
end

function M.search_notes()
  builtin.live_grep({
    prompt_title = "Search Notes",
    cwd = require('pkm.init').config.root_path,
  })
end

function M.find_notes()
  builtin.find_files({
    prompt_title = "Find Files",
    cwd = require('pkm.init').config.root_path,
  })
end

return M
