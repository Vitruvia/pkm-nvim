-- =============================================================================
-- pkm.ui — Fallback UI components (no Telescope dependency)
-- =============================================================================
-- Dependencies : pkm.yaml, pkm.utils, pkm.citations (lazy)
-- Consumed by  : pkm.commands, pkm.telescope (fallback)
--
-- Public API:
--   setup(user_config)       → Initialize with resolved PKM config
--   search_notes(query?)     → Full-text search with vim.ui.select results
--   browse_tags()            → Two-level tag → file picker
--   insert_citation_ui()     → Citation picker fallback (no Telescope)
--   merge_tags_ui()          → Interactive tag merge (fallback for PKMMergeTags)
--   show_stats()             → Show note counts via vim.notify
--   browse(filter_expr?)     → Browse notes with optional filter expression
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
-- SECTION: Search
-- =============================================================================
--- Full-text search across all three PKM folders.
--- Prompts for query if not provided. Opens result in editor and jumps to
--- first matching line. Uses vim.ui.select for result display.
---@param query string|nil Search string; prompts if nil or empty
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

-- =============================================================================
-- SECTION: Note browser
-- =============================================================================

--- Browse PKM notes with optional filter expression. Fallback for PKMBrowse
--- when Telescope is unavailable. Uses vim.ui.select.
---@param filter_expr string|nil
function M.browse(filter_expr)
  local filter = require('pkm.filter')
  local index  = require('pkm.index')

  local all_entries = index.get_all()
  local entries

  if filter_expr and filter_expr ~= '' then
    local tree, err = filter.parse(filter_expr)
    if not tree then
      vim.notify('[pkm] invalid filter: ' .. err, vim.log.levels.ERROR)
      return
    end
    entries = {}
    for _, e in ipairs(all_entries) do
      if filter.eval(tree, e) then entries[#entries + 1] = e end
    end
  else
    entries = all_entries
  end

  if #entries == 0 then
    vim.notify('[pkm] no notes match', vim.log.levels.INFO)
    return
  end

  table.sort(entries, function(a, b) return a.filename < b.filename end)

  vim.ui.select(entries, {
    prompt = filter_expr and ('Browse: ' .. filter_expr) or 'Browse Notes',
    format_item = function(e)
      return e.title .. '  (' .. e.filename .. ')'
    end,
  }, function(sel)
    if sel then vim.cmd('edit ' .. vim.fn.fnameescape(sel.path)) end
  end)
end

--- Tag picker. On selection, opens browse() pre-filtered to tag:<selected>.
function M.browse_tags()
  local tags = require('pkm.citations').get_all_tags()

  if #tags == 0 then
    vim.notify('[pkm] no tags found', vim.log.levels.INFO)
    return
  end

  vim.ui.select(tags, {
    prompt = 'Browse by Tag',
    format_item = function(t) return t end,
  }, function(sel)
    if sel then M.browse('tag:' .. sel) end
  end)
end

-- =============================================================================
-- SECTION: Citation insertion fallback
-- =============================================================================
--- Fallback citation picker using vim.ui.select. Used by PKMInsertCitation
--- when Telescope is unavailable. Delegates insertion to complete_insertion()
--- so frontmatter sync fires on the same path as the Telescope picker.
function M.insert_citation_ui()
  local citations = require('pkm.citations')
  local items = citations.get_citable_items_for_picker()

  if #items == 0 then
    vim.notify("PKM: No citable notes found.", vim.log.levels.INFO)
    return
  end

  vim.ui.select(items, {
    prompt      = "Insert Citation:",
    format_item = function(item) return item.display end,
  }, function(selected)
    if selected then
      citations.complete_insertion(selected)
    end
  end)
end

-- =============================================================================
-- SECTION: Tag merging
-- =============================================================================
--- Interactive tag merge UI. Prompts for a target tag via vim.ui.select,
--- then accepts comma-separated source tags via input. Validates, confirms,
--- then delegates to citations.merge_tags(). Used as fallback when Telescope
--- is unavailable for PKMMergeTags.
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
--- Show note counts per folder via vim.notify.
--- Called by :PKMStats command.
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
