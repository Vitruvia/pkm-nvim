-- lua/pkm/init.lua
local M = {}

-- M.config = default_config

function M.setup(user_config)
  M.config = require('pkm.config').resolve(user_config)

  -- Initialize Modules
  require('pkm.timestamp').setup(M.config)
  require('pkm.yaml').setup(M.config)
  require('pkm.citations').setup(M.config)
  require('pkm.templates').setup(M.config)
  require('pkm.journal').setup(M.config)
  require('pkm.notes').setup(M.config)
  require('pkm.ui').setup(M.config)

  -- Wire commands and keymaps
  require('pkm.commands').register()
  require('pkm.keymaps').register(M.config)
  if M.config.sync.enabled then M.setup_sync_autocmds() end
end 


function M.setup_sync_autocmds()
  local augroup = vim.api.nvim_create_augroup("PKMSync", { clear = true })
  
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      if not filepath:lower():find(".md") then return end
      
      vim.schedule(function()
        local root = M.config.root_path
        local norm_path = filepath:gsub("\\", "/")
        local norm_root = root:gsub("\\", "/")
        if not norm_path:lower():find(norm_root:lower(), 1, true) then return end

        local yaml = require('pkm.yaml')
        local timestamp = require('pkm.timestamp')
        local notes = require('pkm.notes')
        local journal = require('pkm.journal')
        local citations = require('pkm.citations')

        local lines = vim.fn.readfile(filepath)
        if lines[1] == "---" then
            local frontmatter, content_start = yaml.parse_frontmatter(lines)
            if not frontmatter or (frontmatter.cites and type(frontmatter.cites) ~= "table") then
                vim.notify("PKM Error: Frontmatter corrupted. Sync aborted.", vim.log.levels.ERROR)
                return 
            end
            frontmatter.last_updated_on = timestamp.to_iso8601()
            yaml.save_frontmatter(frontmatter, content_start, filepath)
        end

        if filepath:find(M.config.folders.consolidated, 1, true) then notes.sync_filename_on_save() end
        if filepath:find(M.config.folders.journal, 1, true) then journal.sync_filename_on_save() end
        
        -- FIXED: Pass filepath to update references on DISK, so reloading gets everything
        if M.config.sync.auto_sync_on_save then 
            citations.update_references(filepath) 
        end
        
        vim.cmd("checktime")
      end)
    end,
  })
  
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      local root = M.config.root_path
      local norm_path = filepath:gsub("\\", "/")
      local norm_root = root:gsub("\\", "/")
      if not norm_path:lower():find(norm_root:lower(), 1, true) then return end
      if filepath:find(M.config.folders.consolidated, 1, true) then require('pkm.notes').sync_yaml_on_rename() end
      if filepath:find(M.config.folders.journal, 1, true) then require('pkm.journal').sync_yaml_on_rename() end
    end,
  })
end

function M.delete_note_safely()
  local filepath = vim.fn.expand("%:p")
  local root = M.config.root_path
  
  -- Normalization for comparison
  local norm_path = filepath:gsub("\\", "/")
  local norm_root = root:gsub("\\", "/")

  if filepath == "" or not norm_path:lower():find(norm_root:lower(), 1, true) then
    vim.notify("Not a valid PKM note.", vim.log.levels.ERROR)
    return
  end
  
  local filename = vim.fn.fnamemodify(filepath, ":t")
  vim.fn.inputsave()
  local confirm = vim.fn.input(string.format("Delete '%s' and all references? (yes/no): ", filename))
  vim.fn.inputrestore()
  
  if confirm:lower() ~= "yes" then 
    vim.notify("Deletion cancelled.", vim.log.levels.INFO)
    return 
  end
  
  require('pkm.citations').cleanup_deleted_note(filepath)
  vim.cmd("bdelete!")
  
  if vim.fn.delete(filepath) == 0 then
    vim.notify("Note deleted.", vim.log.levels.INFO)
  else
    vim.notify("Failed to delete file.", vim.log.levels.ERROR)
  end
end

return M
