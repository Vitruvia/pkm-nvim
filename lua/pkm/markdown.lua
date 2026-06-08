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
--   setup_symbols(symbols)                     → Register buffer-local iabbrevs and insert-mode keymaps
--   renumber_sequence(start_line, end_line)    → Renumber ordered sequence items in line range
--   renumber_at_cursor()                       → Renumber sequence in paragraph around cursor
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
      lines[i] = line:gsub('^([#]+)', function(h) return '#' .. h end)
    else
      lines[i] = line:gsub('^([#][#]+)', function(h) return h:sub(2) end)
    end
  end

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
end

-- =============================================================================
-- SECTION: Symbol abbreviations
-- =============================================================================

--- Register buffer-local insert-mode abbreviations and keymaps for user-defined
--- symbol expansions. Each entry may have: trigger (iabbrev), key (insert-mode
--- keymap), expansion (the symbol string). Silently skips malformed entries.
--- Call from a BufReadPost autocmd to scope registrations per buffer.
---@param symbols table  List of {trigger?, key?, expansion=string} entries
---@return nil
function M.setup_symbols(symbols)
  if not symbols or #symbols == 0 then return end
  for _, s in ipairs(symbols) do
    if type(s.expansion) ~= 'string' or s.expansion == '' then goto continue end

    if type(s.trigger) == 'string' and s.trigger ~= '' then
      vim.cmd(string.format('iabbrev <buffer> %s %s', s.trigger, s.expansion))
    end

    if type(s.key) == 'string' and s.key ~= '' then
      vim.keymap.set('i', s.key, s.expansion,
        { buffer = true, silent = true, desc = 'PKM: insert ' .. s.expansion })
    end

    ::continue::
  end
end

-- =============================================================================
-- SECTION: Sequence renumbering
-- =============================================================================

--- Return the 1-indexed start and end lines of the paragraph around the cursor,
--- bounded by blank lines or buffer boundaries.
---@return integer, integer
local function paragraph_bounds()
  local cur   = vim.api.nvim_win_get_cursor(0)[1]
  local total = vim.api.nvim_buf_line_count(0)
  local lines = vim.api.nvim_buf_get_lines(0, 0, total, false)

  local s = cur
  while s > 1 and lines[s - 1] ~= '' do s = s - 1 end

  local e = cur
  while e < total and lines[e + 1] ~= '' do e = e + 1 end

  return s, e
end

--- Renumber all ordered-sequence items in the given line range sequentially
--- from 1. The sequence family (style and indentation) is determined by the
--- first matching line in the range; subsequent lines must share the same
--- family to be renumbered. Non-matching lines are preserved unchanged.
---
--- Supported families:
---   Ordered list (dot)    INDENT N. text   any indentation level
---   Ordered list (paren)  INDENT N) text   any indentation level
---   Header inline count   ## N. text       any header level
---   Header inline count   ## N) text       any header level
---   Header suffix count   ## text-N        any header level;
---                                          trailing non-digit annotations preserved
---
--- Family detection order: list → hdr_prefix → hdr_suffix. A line matching
--- hdr_prefix (## N. text) is never treated as hdr_suffix regardless of
--- whether its title text also contains dash+digit sequences.
---@param start_line integer  1-indexed, inclusive
---@param end_line   integer  1-indexed, inclusive
---@return nil
function M.renumber_sequence(start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  local kind   = nil  -- 'list' | 'hdr_prefix' | 'hdr_suffix'
  local indent = nil  -- leading whitespace (list) or '##+ ' (header)
  local sep    = nil  -- '.' or ')' for list/hdr_prefix

  for _, line in ipairs(lines) do
    local ind, s = line:match('^(%s*)%d+([.)]) ')
    if ind then
      kind, indent, sep = 'list', ind, s
      break
    end
    local hdr, s2 = line:match('^(#+%s+)%d+([.)]) ')
    if hdr then
      kind, indent, sep = 'hdr_prefix', hdr, s2
      break
    end
    if line:match('^#+%s') and line:match('%-(%d+)%D*$') then
      kind, indent = 'hdr_suffix', line:match('^(#+%s+)')
      break
    end
  end

  if not kind then
    vim.notify('[pkm] no renumberable sequence found in range', vim.log.levels.WARN)
    return
  end

  local counter   = 1
  local changed   = 0
  local new_lines = {}

  for _, line in ipairs(lines) do
    local replaced = false

    if kind == 'list' then
      local ind, _, s, rest = line:match('^(%s*)(%d+)([.)]) (.*)$')
      if ind == indent and s == sep then
        new_lines[#new_lines + 1] = indent .. counter .. sep .. ' ' .. rest
        counter, changed, replaced = counter + 1, changed + 1, true
      end

    elseif kind == 'hdr_prefix' then
      local hdr, _, s, rest = line:match('^(#+%s+)(%d+)([.)]) (.*)$')
      if hdr == indent and s == sep then
        new_lines[#new_lines + 1] = indent .. counter .. sep .. ' ' .. rest
        counter, changed, replaced = counter + 1, changed + 1, true
      end

    elseif kind == 'hdr_suffix' then
      if line:match('^#+%s') and line:match('^(#+%s+)') == indent then
        local pre, _, suf = line:match('^(.+)%-(%d+)(%D*)$')
        if pre then
          new_lines[#new_lines + 1] = pre .. '-' .. counter .. suf
          counter, changed, replaced = counter + 1, changed + 1, true
        end
      end
    end

    if not replaced then
      new_lines[#new_lines + 1] = line
    end
  end

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, new_lines)
  if changed > 0 then
    vim.notify(
      string.format('[pkm] renumbered %d %s', changed, changed == 1 and 'item' or 'items'),
      vim.log.levels.INFO
    )
  end
end

--- Renumber the ordered sequence in the paragraph surrounding the cursor.
--- Paragraph bounds are determined by blank lines or buffer boundaries.
---@return nil
function M.renumber_at_cursor()
  local s, e = paragraph_bounds()
  M.renumber_sequence(s, e)
end

return M
