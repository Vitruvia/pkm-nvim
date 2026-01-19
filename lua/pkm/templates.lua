-- lua/pkm/templates.lua
local M = {}
local config = {}
local path_sep = package.config:sub(1, 1)

function M.setup(user_config)
  config = user_config
end

local function join_path(...)
  return table.concat({...}, path_sep)
end

function M.get_templates()
  local template_dir = config.folders.templates or "templates"
  local template_path = join_path(config.root_path, template_dir)
  
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

function M.apply_template()
  local templates = M.get_templates()
  
  if #templates == 0 then
    vim.notify("No templates found in " .. join_path(config.root_path, config.folders.templates or "templates"), vim.log.levels.WARN)
    return
  end

  local on_select = function(selection)
    local content = vim.fn.readfile(selection.path)
    local expanded_content = expand_variables(content)
    
    local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_lines(0, row, row, false, expanded_content)
  end

  -- Use Telescope if available
  local has_tele, tele = pcall(require, 'pkm.telescope')
  if has_tele and package.loaded['telescope'] then
    tele.template_picker(templates, on_select)
  else
    vim.ui.select(templates, {
      prompt = "Select Template:",
      format_item = function(item) return item.name end
    }, function(choice)
      if choice then on_select(choice) end
    end)
  end
end

-- Add missing export for telescope integration if needed
function M.template_picker(templates, on_select)
    -- This logic is usually inside telescope.lua, but we can keep shared logic here if needed.
    -- For now, the implementation above delegates back to telescope.lua's picker or vim.ui
end

return M
