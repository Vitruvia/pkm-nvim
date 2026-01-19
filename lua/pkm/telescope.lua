-- lua/pkm/telescope.lua
local M = {}
local citations = require('pkm.citations')

-- Safe require for Telescope
local has_telescope, telescope = pcall(require, 'telescope')
if not has_telescope then
  error("PKM requires telescope.nvim to be installed")
end

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
        -- Insert logic moved here to avoid circular require
        local item = selection.value
        local citation = string.format("%s[%s]", item.type, item.short_id)
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        local line = vim.api.nvim_get_current_line()
        vim.api.nvim_set_current_line(line:sub(1, col) .. citation .. line:sub(col + 1))
        vim.api.nvim_win_set_cursor(0, {row, col + #citation})
        vim.schedule(function() citations.update_references() end)
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
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local tag = selection[1]
        
        -- Open Live Grep pre-filled with the tag
        -- We search for the specific YAML list syntax to be accurate
        -- Pattern: "  - "tagname"" or "  - tagname"
        builtin.grep_string({
          prompt_title = "Notes with tag: " .. tag,
          search = tag, 
          cwd = require('pkm.init').config.root_path
        })
      end)
      return true
    end,
  }):find()
end

-- 3. Search All Notes (File Names)
function M.find_notes()
  builtin.find_files({
    prompt_title = "Find Notes",
    cwd = require('pkm.init').config.root_path,
    hidden = false
  })
end

-- 4. Search Note Content (Grep)
function M.search_notes()
  builtin.live_grep({
    prompt_title = "Search Note Content",
    cwd = require('pkm.init').config.root_path,
  })
end

return M
