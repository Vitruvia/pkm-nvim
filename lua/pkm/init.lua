-- lua/pkm/init.lua
local M = {}

local default_config = {
  root_path = vim.fn.expand('~/Notes'),
  folders = {
    consolidated = "03-Consolidated",
    journal = "02-Journal",
    scratchpad = "01-Scratchpad",
    templates = "templates",
  }
}

M.config = default_config

function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

  -- Ensure paths exist
  if vim.fn.isdirectory(M.config.root_path) == 0 then
    vim.notify("PKM Root not found: " .. M.config.root_path, vim.log.levels.WARN)
  end

  -- Initialize Modules
  require('pkm.citations').setup(M.config)
  
  -- --- Commands ---
  
  -- 1. Citations
  vim.api.nvim_create_user_command('PKMInsertCitation', function()
    require('pkm.telescope').insert_citation_picker()
  end, {})

  vim.api.nvim_create_user_command('PKMUpdateReferences', function()
    require('pkm.citations').update_references()
  end, {})
  
  -- 2. Templates (Requires templates.lua from previous turns)
  vim.api.nvim_create_user_command('PKMApplyTemplate', function()
    require('pkm.templates').apply_template()
  end, {})

  -- 3. Search & Browsing
  vim.api.nvim_create_user_command('PKMFind', function()
    require('pkm.telescope').find_notes()
  end, {})
  
  vim.api.nvim_create_user_command('PKMSearch', function()
    require('pkm.telescope').search_notes()
  end, {})
  
  vim.api.nvim_create_user_command('PKMTags', function()
    require('pkm.telescope').browse_tags()
  end, {})
  
  -- --- Autocommands ---
  local group = vim.api.nvim_create_augroup("PKMAuto", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.md",
    callback = function()
       vim.schedule(function() 
         require('pkm.citations').update_references() 
       end)
    end
  })
end

return M
