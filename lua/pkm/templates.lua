-- =============================================================================
-- pkm.templates — Template application for existing notes
-- =============================================================================
-- Dependencies : pkm.utils
-- Consumed by  : pkm.commands (if a PKMApplyTemplate command is added)
--
-- Templates are .md files in config.folders.templates (default: "templates").
-- Variables {{date}} and {{time}} are expanded on insertion.
-- Template selection always uses vim.ui.select (no Telescope dependency).
--
-- Public API:
--   setup(user_config)  → Initialize with resolved PKM config
--   get_templates()     → {name, path}[] list of available templates
--   apply_template()    → picker + insert template at cursor position
-- =============================================================================
local M = {}

local utils = require('pkm.utils')
local config = {}

-- =============================================================================
-- SECTION: Setup
-- =============================================================================
---@param user_config table Resolved PKM config from pkm.config.resolve()
function M.setup(user_config)
  config = user_config
end

-- =============================================================================
-- SECTION: Template discovery
-- =============================================================================
--- Scan the templates folder and return all .md files as template entries.
--- Creates the templates directory if it does not exist.
---@return {name:string, path:string}[]
function M.get_templates()
  local template_dir = config.folders.templates or "templates"
  local template_path = utils.join(config.root_path, template_dir)
  
  -- Ensure directory exists
  if vim.fn.isdirectory(template_path) == 0 then
    vim.fn.mkdir(template_path, "p")
  end

  local files = vim.fn.glob(template_path .. "/*.md", false, true)
  local templates = {}

  for _, file in ipairs(files) do
    table.insert(templates, {
      name = vim.fn.fnamemodify(file, ":t:r"),
      path = file
    })
  end
  return templates
end

-- =============================================================================
-- SECTION: Variable expansion
-- =============================================================================
local function expand_variables(lines)
  local new_lines = {}
  local date_str = os.date("%Y-%m-%d")
  local time_str = os.date("%H:%M")
  
  for _, line in ipairs(lines) do
    local expanded = line:gsub("{{date}}", date_str)
    expanded = expanded:gsub("{{time}}", time_str)
    table.insert(new_lines, expanded)
  end
  return new_lines
end

-- =============================================================================
-- SECTION: Application
-- =============================================================================
--- Insert a selected template at the current cursor line.
--- Expands {{date}} and {{time}} variables before inserting.
--- Uses vim.ui.select for template picking (no Telescope dependency).
function M.apply_template()
  local templates = M.get_templates()

  if #templates == 0 then
    vim.notify(
      "No templates found in " .. utils.join(config.root_path, config.folders.templates or "templates"),
      vim.log.levels.WARN
    )
    return
  end

  local on_select = function(selection)
    if not selection then return end
    local content          = vim.fn.readfile(selection.path)
    local expanded_content = expand_variables(content)
    local row, _           = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_lines(0, row, row, false, expanded_content)
  end

  vim.ui.select(templates, {
    prompt      = "Select Template:",
    format_item = function(item) return item.name end,
  }, on_select)
end

return M
