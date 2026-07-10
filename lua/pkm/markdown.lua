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
--   setup_symbols(symbols)                     → Register buffer-local insert-mode keymaps (trigger and key)
--   renumber_sequence(start_line, end_line)    → Renumber ordered sequence items in line range
--   renumber_at_cursor()                       → Renumber sequence in paragraph around cursor
--   convert_list(start_line, end_line, direction?) → Convert list ordered ↔ unordered
--   convert_list_at_cursor(direction?)             → Same, paragraph around cursor
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

--- Register buffer-local insert-mode keymaps for user-defined symbol expansions.
--- Each entry may have: trigger (exact-sequence keymap fired immediately, no
--- trailing character), key (key-combination keymap), expansion (the symbol
--- string). Both use vim.keymap.set('i', ...). Silently skips malformed entries.
--- Call from a BufReadPost autocmd to scope registrations per buffer.
---@param symbols table  List of {trigger?, key?, expansion=string} entries
---@return nil
function M.setup_symbols(symbols)
  if not symbols or #symbols == 0 then return end
  for _, s in ipairs(symbols) do
    if type(s.expansion) ~= 'string' or s.expansion == '' then goto continue end

    if type(s.trigger) == 'string' and s.trigger ~= '' then
      vim.keymap.set('i', s.trigger, s.expansion,
        { buffer = true, silent = true, desc = 'PKM: insert ' .. s.expansion })
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
--- from 1. Family is detected from the first matching line in the range.
--- Non-matching lines are preserved unchanged.
---
--- Supported families (detection order: list → hdr_prefix → hdr_suffix):
---   list (plain)      BLOCKQUOTE? INDENT N[.)] text    — any indent depth
---   list (emph)       BLOCKQUOTE? INDENT *N*[.)] text  — single or double *
---   hdr_prefix        BLOCKQUOTE? ## N[.)] text        — any header level
---   hdr_suffix        BLOCKQUOTE? ## text-N            — trailing annotation preserved
---
--- Nested list items use a per-level counter stack keyed by effective depth
--- (each '>' in the blockquote prefix = 2; each space = 1; each tab = 4).
--- Sub-lists restart from 1 under each new parent item. Header families use
--- a single flat counter. Blockquote prefixes are stripped before matching
--- and restored in output unchanged.
---@param start_line integer  1-indexed, inclusive
---@param end_line   integer  1-indexed, inclusive
---@return nil
function M.renumber_sequence(start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  -- ── helpers ──────────────────────────────────────────────────────────────

  local function strip_bq(line)
    local bq, rest = line:match('^(>+%s*)(.*)')
    return (bq or ''), (rest or line)
  end

  local function ind_depth(ind)
    local d = 0
    for c in ind:gmatch('.') do d = d + (c == '\t' and 4 or 1) end
    return d
  end

  local function eff_depth(bq, ind)
    local d = 0
    for _ in bq:gmatch('>') do d = d + 2 end
    return d + ind_depth(ind)
  end

  -- ── 1. detect family ─────────────────────────────────────────────────────

  local kind   = nil
  local sep    = nil
  local em_pat = nil

  for _, line in ipairs(lines) do
    local _, rest = strip_bq(line)

    -- Plain ordered list: N[.)] with optional space+body or end of line.
    local s = rest:match('^%s*%d+([.)]) ')
           or rest:match('^%s*%d+([.)])%s*$')
    if s then kind, sep = 'list', s; break end

    -- Bold-line list: **N. body** — whole item wrapped in double asterisks.
    s = rest:match('^%s*%*%*%d+([.)]) .-%*%*$')
    if s then kind, sep = 'list_bold_line', s; break end

    -- Emph single: *N*[.)] body
    s = rest:match('^%s*%*%d+%*([.)]) ')
     or rest:match('^%s*%*%d+%*([.)])%s*$')
    if s then kind, sep, em_pat = 'list_emph', s, '%*'; break end

    -- Emph double: **N**[.)] body
    s = rest:match('^%s*%*%*%d+%*%*([.)]) ')
     or rest:match('^%s*%*%*%d+%*%*([.)])%s*$')
    if s then kind, sep, em_pat = 'list_emph', s, '%*%*'; break end

    s = rest:match('^#+%s+%d+([.)]) ')
    if s then kind, sep = 'hdr_prefix', s; break end

    if rest:match('^#+%s') and rest:match('%-(%d+)%D*$') then
      kind = 'hdr_suffix'; break
    end
  end

  if not kind then
    vim.notify('[pkm] no renumberable sequence found in range', vim.log.levels.WARN)
    return
  end

  -- ── 2. renumber ──────────────────────────────────────────────────────────

  -- Per-level counter stack for list families.
  -- Stepping to a shallower depth clears all deeper entries so sub-lists
  -- restart from 1 under each new parent item.
  local counters = {}

  local function next_count(d)
    for k in pairs(counters) do if k > d then counters[k] = nil end end
    counters[d] = (counters[d] or 0) + 1
    return counters[d]
  end

  local hdr_counter = 0
  local em_str      = em_pat == '%*%*' and '**' or '*'
  local changed     = 0
  local new_lines   = {}

  for _, line in ipairs(lines) do
    local replaced = false
    local bq, rest = strip_bq(line)

    if kind == 'list' then
      -- Two-pass: try with body text, fall back to empty item (no space after sep).
      local ind, _, s, body = rest:match('^(%s*)(%d+)([.)]) (.*)$')
      if not (ind and s == sep) then
        local ind2, _, s2 = rest:match('^(%s*)(%d+)([.)])%s*$')
        if ind2 and s2 == sep then ind, s, body = ind2, s2, nil end
      end
      if ind then
        local n = next_count(eff_depth(bq, ind))
        new_lines[#new_lines + 1] = body ~= nil
          and bq .. ind .. n .. sep .. ' ' .. body
          or  bq .. ind .. n .. sep
        changed, replaced = changed + 1, true
      end

    elseif kind == 'list_emph' then
      local pat   = '^(%s*)' .. em_pat .. '(%d+)' .. em_pat .. '([.)]) (.*)$'
      local pat_e = '^(%s*)' .. em_pat .. '(%d+)' .. em_pat .. '([.)])%s*$'
      local ind, _, s, body = rest:match(pat)
      if not (ind and s == sep) then
        local ind2, _, s2 = rest:match(pat_e)
        if ind2 and s2 == sep then ind, s, body = ind2, s2, nil end
      end
      if ind then
        local n = next_count(eff_depth(bq, ind))
        new_lines[#new_lines + 1] = body ~= nil
          and bq .. ind .. em_str .. n .. em_str .. sep .. ' ' .. body
          or  bq .. ind .. em_str .. n .. em_str .. sep
        changed, replaced = changed + 1, true
      end

    elseif kind == 'list_bold_line' then
      -- **N. body** — double asterisks wrap the whole item.
      local ind, _, s, body = rest:match('^(%s*)%*%*(%d+)([.)]) (.-)%*%*$')
      if ind and s == sep then
        local n = next_count(eff_depth(bq, ind))
        new_lines[#new_lines + 1] = bq .. ind .. '**' .. n .. sep .. ' ' .. body .. '**'
        changed, replaced = changed + 1, true
      end

    elseif kind == 'hdr_prefix' then
      local hdr, _, s, body = rest:match('^(#+%s+)(%d+)([.)]) (.*)$')
      if hdr and s == sep then
        hdr_counter = hdr_counter + 1
        new_lines[#new_lines + 1] = bq .. hdr .. hdr_counter .. sep .. ' ' .. body
        changed, replaced = changed + 1, true
      end

    elseif kind == 'hdr_suffix' then
      if rest:match('^#+%s') then
        local pre, _, suf = rest:match('^(.+)%-(%d+)(%D*)$')
        if pre then
          hdr_counter = hdr_counter + 1
          new_lines[#new_lines + 1] = bq .. pre .. '-' .. hdr_counter .. suf
          changed, replaced = changed + 1, true
        end
      end
    end

    if not replaced then new_lines[#new_lines + 1] = line end
  end

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, new_lines)
  if changed > 0 then
    vim.notify(
      string.format('[pkm] renumbered %d %s', changed, changed == 1 and 'item' or 'items'),
      vim.log.levels.INFO
    )
  end

  -- Re-sync tree-sitter after buffer modification to prevent
  -- 'end_row out of range' in the decoration provider.
  vim.schedule(function()
    local bufnr = vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_is_valid(bufnr) then
      local ok, mode = pcall(require, 'pkm.mode')
      if ok and mode.is_active() then
        pcall(vim.treesitter.start, bufnr, 'markdown')
      end
    end
  end)
end

--- Renumber the ordered sequence in the paragraph surrounding the cursor.
--- Paragraph bounds are determined by blank lines or buffer boundaries.
---@return nil
function M.renumber_at_cursor()
  local s, e = paragraph_bounds()
  M.renumber_sequence(s, e)
end

-- =============================================================================
-- SECTION: List conversion
-- =============================================================================

--- Convert list items between ordered and unordered in the given range.
--- Direction is auto-detected: all ordered → to_unordered; all unordered →
--- to_ordered; mixed → prompts. If multiple indent depths exist, prompts for
--- maximum depth to convert. Items already in the target format are preserved
--- (ordered items are renumbered to maintain sequence; unordered items are
--- left as-is). Blockquote prefixes are handled the same as renumber_sequence.
---@param start_line integer   1-indexed, inclusive
---@param end_line   integer   1-indexed, inclusive
---@param direction  string|nil  'to_ordered'|'to_unordered'; nil = auto-detect
---@return nil
function M.convert_list(start_line, end_line, direction)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  local function strip_bq(line)
    local bq, rest = line:match('^(>+%s*)(.*)')
    return (bq or ''), (rest or line)
  end

  local function ind_depth(ind)
    local d = 0
    for c in ind:gmatch('.') do d = d + (c == '\t' and 4 or 1) end
    return d
  end

  -- Collect list items.
  local items = {}
  for i, line in ipairs(lines) do
    local bq, rest = strip_bq(line)
    local ind, _, sep, body = rest:match('^(%s*)(%d+)([.)]) (.*)$')
    if ind then
      items[#items + 1] = {
        idx = i, type = 'ordered', bq = bq, ind = ind,
        depth = ind_depth(ind), sep = sep, body = body,
      }
    else
      local ind2, marker, body2 = rest:match('^(%s*)([-*+]) (.*)$')
      if ind2 then
        items[#items + 1] = {
          idx = i, type = 'unordered', bq = bq, ind = ind2,
          depth = ind_depth(ind2), marker = marker, body = body2,
        }
      end
    end
  end

  if #items == 0 then
    vim.notify('[pkm] no list items found in range', vim.log.levels.WARN)
    return
  end

  local has_ordered, has_unordered = false, false
  local depth_set = {}
  for _, it in ipairs(items) do
    if it.type == 'ordered'   then has_ordered   = true end
    if it.type == 'unordered' then has_unordered = true end
    depth_set[it.depth] = true
  end

  local depth_list = {}
  for d in pairs(depth_set) do depth_list[#depth_list + 1] = d end
  table.sort(depth_list)
  local has_multiple_depths = #depth_list > 1

  -- Core conversion logic.
  local function do_convert(dir, max_depth)
    local counters = {}
    local function next_ordered(depth)
      for k in pairs(counters) do if k > depth then counters[k] = nil end end
      counters[depth] = (counters[depth] or 0) + 1
      return counters[depth]
    end

    local new_lines = {}
    local changed = 0

    for i, line in ipairs(lines) do
      local replaced = false
      for _, it in ipairs(items) do
        if it.idx == i then
          if it.depth <= max_depth then
            if dir == 'to_ordered' and it.type == 'unordered' then
              local n = next_ordered(it.depth)
              new_lines[#new_lines + 1] = it.bq .. it.ind .. n .. '. ' .. it.body
              changed, replaced = changed + 1, true
            elseif dir == 'to_unordered' and it.type == 'ordered' then
              new_lines[#new_lines + 1] = it.bq .. it.ind .. '- ' .. it.body
              changed, replaced = changed + 1, true
            else
              -- Already correct type; still advance ordered counter to keep sequence.
              if dir == 'to_ordered' and it.type == 'ordered' then
                next_ordered(it.depth)
              end
            end
          end
          break
        end
      end
      if not replaced then new_lines[#new_lines + 1] = line end
    end

    vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, new_lines)

    if changed > 0 then
      vim.notify(string.format('[pkm] converted %d list item%s',
        changed, changed == 1 and '' or 's'), vim.log.levels.INFO)
    else
      vim.notify('[pkm] no items converted (already in target format)',
        vim.log.levels.INFO)
    end

    vim.schedule(function()
      local bufnr = vim.api.nvim_get_current_buf()
      if vim.api.nvim_buf_is_valid(bufnr) then
        local ok, mode = pcall(require, 'pkm.mode')
        if ok and mode.is_active() then
          pcall(vim.treesitter.start, bufnr, 'markdown')
        end
      end
    end)
  end

  -- Prompt for depth if multiple levels, then convert.
  local function ask_depth_then_convert(dir)
    if not has_multiple_depths then
      do_convert(dir, math.huge)
      return
    end
    local opts = {}
    for _, d in ipairs(depth_list) do
      opts[#opts + 1] = string.format('Up to level %d (depth ≤ %d)', d, d)
    end
    opts[#opts + 1] = 'All levels'
    vim.ui.select(opts, {
      prompt = string.format('Convert list — %d depth levels found:', #depth_list),
    }, function(choice)
      if not choice then return end
      if choice == 'All levels' then
        do_convert(dir, math.huge)
      else
        do_convert(dir, tonumber(choice:match('%d+')) or math.huge)
      end
    end)
  end

  -- Determine direction, then proceed.
  if direction then
    ask_depth_then_convert(direction)
  elseif has_ordered and not has_unordered then
    ask_depth_then_convert('to_unordered')
  elseif has_unordered and not has_ordered then
    ask_depth_then_convert('to_ordered')
  else
    vim.ui.select({ 'Convert to ordered', 'Convert to unordered' }, {
      prompt = 'Mixed list — convert to:',
    }, function(choice)
      if not choice then return end
      ask_depth_then_convert(
        choice == 'Convert to ordered' and 'to_ordered' or 'to_unordered')
    end)
  end
end

--- Convert the list around the cursor (paragraph-bounded).
---@param direction string|nil  'to_ordered'|'to_unordered'; nil = auto-detect
---@return nil
function M.convert_list_at_cursor(direction)
  local s, e = paragraph_bounds()
  M.convert_list(s, e, direction)
end

return M
