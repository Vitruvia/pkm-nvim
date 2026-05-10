-- lua/pkm/ui.lua
-- UI components and search for PKM system

local M = {}
local utils = require('pkm.utils')
local config = {}
local yaml = nil

function M.setup(user_config)
  config = user_config
  yaml = require('pkm.yaml')
end

--- Search all notes (Feature 5 placeholder)
--- @param query string Search query
function M.search_notes(query)
  -- Collect all markdown files
  local search_paths = {
    utils.join(config.root_path, config.folders.consolidated),
    utils.join(config.root_path, config.folders.journal),
    utils.join(config.root_path, config.folders.scratchpad),
  }
  
  local results = {}
  
  -- If no query provided, prompt for it
  if not query or query == "" then
    vim.fn.inputsave()
    query = vim.fn.input("Search: ")
    vim.fn.inputrestore()
    
    if not query or query == "" then
      vim.notify("Search cancelled", vim.log.levels.INFO)
      return
    end
  end
  
  local query_lower = query:lower()
  
  for _, search_path in ipairs(search_paths) do
    local files = vim.fn.glob(search_path .. utils.sep .. "*.md", false, true)
    
    for _, file in ipairs(files) do
      local content = vim.fn.readfile(file)
      local matches = {}
      
      for line_num, line in ipairs(content) do
        if line:lower():find(query_lower, 1, true) then
          table.insert(matches, {
            line_num = line_num,
            text = line:sub(1, 100), -- Truncate long lines
          })
        end
      end
      
      if #matches > 0 then
        table.insert(results, {
          path = file,
          filename = vim.fn.fnamemodify(file, ":t"),
          matches = matches,
          match_count = #matches,
        })
      end
    end
  end
  
  if #results == 0 then
    vim.notify("No results found for: " .. query, vim.log.levels.INFO)
    return
  end
  
  -- Display results
  local display_items = {}
  for _, result in ipairs(results) do
    local display = string.format("%s (%d matches)", result.filename, result.match_count)
    table.insert(display_items, {
      display = display,
      result = result,
    })
  end
  
  vim.ui.select(display_items, {
    prompt = string.format("Search results for '%s':", query),
    format_item = function(item) return item.display end,
  }, function(selected)
    if selected then
      vim.cmd("edit " .. vim.fn.fnameescape(selected.result.path))
      
      -- Jump to first match
      if #selected.result.matches > 0 then
        vim.api.nvim_win_set_cursor(0, {selected.result.matches[1].line_num, 0})
      end
    end
  end)
end

--- Show statistics window
--- @param stats table Statistics data
function M.show_stats_window(stats)
  -- Create buffer for stats
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  -- Build stats content
  local lines = {
    "=== PKM Statistics ===",
    "",
    "Notes:",
    string.format("  Total: %d", stats.total_notes),
    string.format("  Journals: %d", stats.total_journals),
    string.format("  Scratchpads: %d", stats.total_scratchpads),
    string.format("  Citations: %d", stats.total_citations),
    "",
    "Notes by Status:",
  }
  
  for status, count in pairs(stats.notes_by_status) do
    table.insert(lines, string.format("  %s: %d", status, count))
  end
  
  table.insert(lines, "")
  table.insert(lines, "Top Tags:")
  
  -- Sort tags by count
  local sorted_tags = {}
  for tag, count in pairs(stats.notes_by_tag) do
    table.insert(sorted_tags, {tag = tag, count = count})
  end
  table.sort(sorted_tags, function(a, b) return a.count > b.count end)
  
  for i = 1, math.min(10, #sorted_tags) do
    table.insert(lines, string.format("  %s: %d", sorted_tags[i].tag, sorted_tags[i].count))
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  -- Create floating window
  local width = 50
  local height = #lines + 2
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = 'rounded',
    title = " PKM Statistics ",
    title_pos = 'center',
  }
  
  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Close on any key
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
end

--- Tag browser (Feature 1 - for future enhancement)
--- Shows all tags and allows navigation
function M.browse_tags()
  -- Collect tags from all notes
  local all_paths = {
    utils.join(config.root_path, config.folders.consolidated),
    utils.join(config.root_path, config.folders.journal),
  }
  
  local tag_files = {}
  
  for _, search_path in ipairs(all_paths) do
    local files = vim.fn.glob(search_path .. utils.sep .. "*.md", false, true)
    
    for _, file in ipairs(files) do
      local content = vim.fn.readfile(file)
      local frontmatter, _ = yaml.parse_frontmatter(content)
      
      if frontmatter and frontmatter.tags then
        for _, tag in ipairs(frontmatter.tags) do
          if not tag_files[tag] then
            tag_files[tag] = {}
          end
          table.insert(tag_files[tag], {
            path = file,
            filename = vim.fn.fnamemodify(file, ":t"),
          })
        end
      end
    end
  end
  
  if not next(tag_files) then
    vim.notify("No tags found", vim.log.levels.INFO)
    return
  end
  
  -- Create tag list
  local tag_list = {}
  for tag, files in pairs(tag_files) do
    table.insert(tag_list, {
      tag = tag,
      count = #files,
      files = files,
    })
  end
  
  table.sort(tag_list, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.tag < b.tag
  end)
  
  -- First selection: choose tag
  vim.ui.select(tag_list, {
    prompt = "Browse by tag:",
    format_item = function(item)
      return string.format("%s (%d)", item.tag, item.count)
    end,
  }, function(selected_tag)
    if not selected_tag then return end
    
    -- Second selection: choose file
    vim.ui.select(selected_tag.files, {
      prompt = string.format("Files tagged '%s':", selected_tag.tag),
      format_item = function(item) return item.filename end,
    }, function(selected_file)
      if selected_file then
        vim.cmd("edit " .. vim.fn.fnameescape(selected_file.path))
      end
    end)
  end)
end

--- Enhanced note selector with filtering
--- This is for integration with Telescope in the future
--- @param notes table Array of note items
--- @param prompt string Prompt text
--- @param callback function Selection callback
function M.select_note_enhanced(notes, prompt, callback)
  -- Check if Telescope is available
  local has_telescope, telescope = pcall(require, "telescope")
  
  if has_telescope then
    -- Use Telescope for enhanced selection
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    
    pickers.new({}, {
      prompt_title = prompt,
      finder = finders.new_table {
        results = notes,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.display,
          }
        end,
      },
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            callback(selection.value)
          else
            callback(nil)
          end
        end)
        return true
      end,
    }):find()
  else
    -- Fallback to vim.ui.select
    vim.ui.select(notes, {
      prompt = prompt,
      format_item = function(item) return item.display end,
    }, callback)
  end
end

--- Graph view placeholder (Feature 2 - for future implementation)
function M.show_graph()
  vim.notify("Graph view not yet implemented", vim.log.levels.INFO)
  -- This would show a visual graph of note connections
  -- Could use graphviz or similar for visualization
end

--- Analytics dashboard placeholder (Feature 8 - for future implementation)
function M.show_analytics()
  -- This would show:
  -- - Reading time estimates
  -- - Word counts per note/journal
  -- - Writing patterns (when you write most)
  -- - Connection density
  -- - Growth over time
  vim.notify("Analytics dashboard not yet implemented", vim.log.levels.INFO)
end

function M.merge_tags_ui()
  local citations_mod = require('pkm.citations')
  local all_tags = citations_mod.get_all_tags()

  if #all_tags == 0 then
    vim.notify("PKM: No tags found.", vim.log.levels.INFO)
    return
  end

  -- Step 1: pick target from a list
  vim.ui.select(all_tags, {
    prompt = "Merge Tags — Pick TARGET tag (sources will be typed next)",
  }, function(target)
    if not target then return end

    -- Step 2: show available tags and let the user type sources
    local available = vim.tbl_filter(function(t) return t ~= target end, all_tags)
    local available_str = table.concat(available, "  |  ")

    vim.notify("Available tags:\n" .. available_str, vim.log.levels.INFO)

    vim.fn.inputsave()
    local raw = vim.fn.input(
      string.format("Sources to merge into '%s' (comma-separated): ", target)
    )
    vim.fn.inputrestore()

    if not raw or raw:match("^%s*$") then
      vim.notify("PKM: No sources entered. Merge cancelled.", vim.log.levels.INFO)
      return
    end

    -- Parse and validate
    local sources = {}
    local source_set = {}
    local invalid = {}
    local valid_set = {}
    for _, t in ipairs(available) do valid_set[t] = true end

    for entry in raw:gmatch("[^,]+") do
      local t = entry:match("^%s*(.-)%s*$")
      if t ~= "" then
        if valid_set[t] then
          if not source_set[t] then
            source_set[t] = true
            table.insert(sources, t)
          end
        else
          table.insert(invalid, t)
        end
      end
    end

    if #invalid > 0 then
      vim.notify(
        "PKM: Unknown tags (ignored): " .. table.concat(invalid, ", "),
        vim.log.levels.WARN
      )
    end

    if #sources == 0 then
      vim.notify("PKM: No valid source tags. Merge cancelled.", vim.log.levels.INFO)
      return
    end

    -- Confirm
    local src_str = table.concat(sources, ", ")
    vim.fn.inputsave()
    local answer = vim.fn.input(
      string.format("Merge [%s] → '%s'? (y/N): ", src_str, target), "n"
    )
    vim.fn.inputrestore()

    if answer:lower() ~= "y" then
      vim.notify("PKM: Tag merge cancelled.", vim.log.levels.INFO)
      return
    end

    local count = citations_mod.merge_tags(sources, target)
    vim.notify(
      string.format("PKM: Merged [%s] → '%s' in %d file(s).", src_str, target, count),
      vim.log.levels.INFO
    )
  end)
end

--- Show a statistics window with note counts per folder type.
function M.show_stats()
  local folders = {
    { label = "Consolidated", path = utils.join(config.root_path, config.folders.consolidated) },
    { label = "Journal",      path = utils.join(config.root_path, config.folders.journal) },
    { label = "Scratchpad",   path = utils.join(config.root_path, config.folders.scratchpad) },
  }

  local lines = { "PKM Statistics", string.rep("─", 30), "" }
  local total = 0

  for _, folder in ipairs(folders) do
    local files = vim.fn.glob(folder.path .. utils.sep .. "*.md", false, true)
    local count = type(files) == "table" and #files or 0
    total = total + count
    table.insert(lines, string.format("  %-16s %d notes", folder.label .. ":", count))
  end

  table.insert(lines, "")
  table.insert(lines, string.format("  %-16s %d notes", "Total:", total))
  table.insert(lines, "")
  table.insert(lines, "Root: " .. config.root_path)

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

return M
