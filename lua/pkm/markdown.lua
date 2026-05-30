-- =============================================================================
-- pkm.markdown — General markdown editing utilities
-- =============================================================================
-- Dependencies : none
-- Consumed by  : pkm.commands (lazy require from command handlers)
--
-- Editing helpers for markdown files. No PKM-specific dependencies;
-- all functions operate on the current buffer via the Neovim API.
-- No setup() is needed — require lazily from command handlers.
--
-- Public API:
--   append_next_header()                       → Duplicate current header with counter +1, append at EOF
--   shift_header_level(direction, start, end)  → Shift header '#'-level up or down in line range
-- =============================================================================

local M = {}

-- =============================================================================
-- SECTION: Header counter
-- =============================================================================

--- Duplicate the header on the current line with its trailing counter incremented
--- by one, appending the result at the end of the buffer after a blank separator.
--- Trailing non-digit annotations (e.g. " (FGV)") are preserved unchanged.
--- Skips the blank separator if the buffer already ends with an empty line.
---@return nil
function M.append_next_header()
  local line = vim.api.nvim_get_current_line()

  -- Greedy (.*) forces %-(%d+) to match the LAST dash+counter in the line,
  -- so prefixes with dashes or numbers (e.g. "DirAdm-CEBRASPE") are safe.
  local prefix, num_str, suffix = line:match('^(.*)%-(%d+)(%D*)$')

  if not prefix then
    vim.notify('[pkm] no incrementable counter on current line', vim.log.levels.WARN)
    return
  end

  local new_header = prefix .. '-' .. tostring(tonumber(num_str) + 1) .. suffix

  local last      = vim.api.nvim_buf_line_count(0)
  local last_line = vim.api.nvim_buf_get_lines(0, last - 1, last, false)[1]
  local to_append = (last_line == '') and { new_header } or { '', new_header }

  vim.api.nvim_buf_set_lines(0, last, last, false, to_append)
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
end

-- =============================================================================
-- SECTION: Header level
-- =============================================================================

--- Shift the Markdown header level of all header lines in the given range.
--- "up"   adds one '#'   to every header line (## → ###).
--- "down" removes one '#' from headers with 2+ '#' (### → ##);
---        level-1 headers (# ...) are left unchanged to avoid losing structure.
--- Non-header lines are passed through unmodified.
---@param direction string   "up" to increase level, "down" to decrease
---@param start_line integer First line of range (1-indexed)
---@param end_line integer   Last line of range (1-indexed, inclusive)
---@return nil
function M.shift_header_level(direction, start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  for i, line in ipairs(lines) do
    if direction == 'up' then
      -- Prepend one '#' to any line that starts with one or more '#'
      lines[i] = line:gsub('^([#]+)', function(h) return '#' .. h end)
    else
      -- Remove the leading '#' only when there are 2 or more (level 2+)
      -- [#][#]+ matches exactly two or more '#', leaving level-1 untouched
      lines[i] = line:gsub('^([#][#]+)', function(h) return h:sub(2) end)
    end
  end

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
end

return M
