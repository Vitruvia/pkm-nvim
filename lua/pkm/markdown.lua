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
--   append_global_header()                     → Next sibling header (max counter +1) at the section's end
--   shift_header_level(direction, start, end)  → Shift header '#'-level up or down in line range
--   find_heading_target(lines, cursor, opts)   → Line of the next/previous ATX heading, or nil (pure)
--   goto_heading(opts)                         → Move the cursor there; true when it moved
--   setup_symbols(symbols)                     → Register buffer-local insert-mode keymaps (trigger and key)
--   renumber_sequence(start_line, end_line)    → Renumber one ordered family in line range
--   renumber_at_cursor()                       → Renumber sequence in paragraph around cursor
--   renumber_legal(start_line, end_line)       → Nested legal renumber (Art/§/inciso/alínea/subalínea)
--   renumber_range(start_line, end_line)       → Route a range: nested legal if ≥2 levels, else single-family
--   convert_list(start_line, end_line, direction?) → Convert list ordered ↔ unordered
--   convert_list_at_cursor(direction?)             → Same, paragraph around cursor
--   wrap_range(start_line, end_line)           → Structure-aware reflow to textwidth (Option A indent)
--   wrap_at_cursor()                           → Same, paragraph around cursor
--   formatexpr()                               → 'formatexpr' hook so gq/gw route through wrap_range
-- =============================================================================

local M = {}

-- =============================================================================
-- SECTION: Shared numbering helpers
-- =============================================================================
-- Used by both renumber_sequence (single-family, depth-keyed) and renumber_legal
-- (nested, marker-type-keyed).

--- Split a leading blockquote prefix (`> `, `>> `, …) from the rest of a line.
---@param line string
---@return string bq, string rest
local function strip_bq(line)
  local bq, rest = line:match('^(>+%s*)(.*)')
  return (bq or ''), (rest or line)
end

--- Positional integer → uppercase Roman numeral (I, II, III …). Standard
--- subtractive form; nil outside 1..3999.
local function to_roman(n)
  if n < 1 or n > 3999 then return nil end
  local map = { { 1000, 'M' }, { 900, 'CM' }, { 500, 'D' }, { 400, 'CD' },
                { 100, 'C' }, { 90, 'XC' }, { 50, 'L' }, { 40, 'XL' },
                { 10, 'X' }, { 9, 'IX' }, { 5, 'V' }, { 4, 'IV' }, { 1, 'I' } }
  local out = {}
  for _, p in ipairs(map) do
    while n >= p[1] do out[#out + 1] = p[2]; n = n - p[1] end
  end
  return table.concat(out)
end

--- Positional integer → lowercase-letter label (a … z, aa, ab …). Bijective
--- base-26 (no "zero" digit): 1→a, 26→z, 27→aa. nil below 1.
local function to_alpha(n)
  if n < 1 then return nil end
  local out = {}
  while n > 0 do
    local r = (n - 1) % 26
    out[#out + 1] = string.char(97 + r)   -- 97 = 'a'
    n = math.floor((n - 1) / 26)
  end
  local rev = {}
  for i = #out, 1, -1 do rev[#rev + 1] = out[i] end
  return table.concat(rev)
end

local ROMAN_VAL = { i = 1, v = 5, x = 10, l = 50, c = 100, d = 500, m = 1000 }

--- Lowercase roman numeral → integer, or nil if the token holds a non-roman
--- letter. Right-to-left, subtracting any symbol below the running maximum.
local function from_roman(s)
  local total, prev = 0, 0
  for k = #s, 1, -1 do
    local v = ROMAN_VAL[s:sub(k, k)]
    if not v then return nil end
    if v < prev then total = total - v else total = total + v; prev = v end
  end
  return total
end

--- True only for a *canonical* lowercase roman numeral (a subalínea marker): the
--- token must round-trip through to_roman, so ordinary words made of roman
--- letters (civil., mil., mix., did.) are rejected — they parse but do not
--- re-encode to themselves.
local function is_valid_roman(s)
  local n = from_roman(s)
  return n ~= nil and n >= 1 and to_roman(n):lower() == s
end

--- Brazilian legal ordinal rule (LC 95/1998, art. 10, III): ordinal (with the
--- `º` indicator) up to the ninth, cardinal from the tenth on.
local function legal_ordinal(n)
  if n <= 9 then return tostring(n) .. 'º' end
  return tostring(n)
end

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
-- SECTION: Header navigation
-- =============================================================================
--
-- What Neovim already does, checked in the runtime rather than assumed:
-- ftplugin/markdown.lua maps `]]` and `[[` to `vim.treesitter._headings.jump`,
-- which moves to the next/previous heading of **any** level. So the any-level
-- jump is not the gap. What that motion does not do is: honour a count (the
-- runtime file says `todo(clason): support count`), restrict the jump to a
-- level — `jump()` accepts `opts.level` but the mappings never pass it, so
-- same-level motion is unreachable — leave a jumplist entry, work in Visual
-- mode (there the older regex mapping takes over, and it misses `######`), or
-- work at all without the tree-sitter markdown parser. This section fills
-- exactly those, and leaves `]]`/`[[` alone.
--
-- Setext headings (underlined with = or -) are out of scope: PKM notes are
-- written with ATX headings, and `---` is also the frontmatter delimiter.

--- Every ATX heading in `lines`, in buffer order, as { lnum, level }.
--- Skips YAML frontmatter (where `# ...` is a comment) and fenced code blocks
--- (where it is usually shell), so neither can be jumped to.
---@param lines string[]
---@return table[]  list of { lnum: integer, level: integer }
local function scan_headings(lines)
  local out   = {}
  local fence = nil     -- opening fence marker while inside a code block
  local i     = 1

  -- Frontmatter only counts when it opens the very first line.
  if lines[1] and lines[1]:match('^%-%-%-%s*$') then
    i = 2
    while i <= #lines and not lines[i]:match('^[%-%.][%-%.][%-%.]%s*$') do i = i + 1 end
    i = i + 1
  end

  while i <= #lines do
    local line = lines[i]

    if fence then
      local close = line:match('^%s*([`~]+)%s*$')
      if close and close:sub(1, 1) == fence:sub(1, 1) and #close >= #fence then
        fence = nil
      end
    else
      local open = line:match('^%s?%s?%s?([`~][`~][`~]+)')
      if open then
        fence = open
      else
        -- ATX: up to three leading spaces, 1-6 '#', then a space or line end.
        -- The required separator is what keeps a `#tag` from being a heading.
        local hashes = line:match('^%s?%s?%s?(#+)%s') or line:match('^%s?%s?%s?(#+)%s*$')
        if hashes and #hashes <= 6 then
          out[#out + 1] = { lnum = i, level = #hashes }
        end
      end
    end

    i = i + 1
  end

  return out
end

--- Scan a buffer's ATX headings, skipping any inside code fences and the
--- frontmatter. Exposed for section-aware operations (e.g.
--- `pkm.notes.write_section`).
---@param lines string[]
---@return { lnum: integer, level: integer }[]
M.scan_headings = scan_headings

--- Create the next sibling header at the end of the current section.
---
--- Where `append_next_header` takes the current line's counter +1 and appends it
--- at end-of-buffer, this reads the whole section: it finds the header the cursor
--- sits in, takes the highest `-N` counter among the same-level, same-prefix
--- headers within the enclosing block (bounded by any shallower header), and
--- inserts `<prefix>-<max+1><suffix>` at the *end of that block* — after every
--- sibling and its sub-content, before the next higher-level header (or at EOF).
--- The cursor moves to the new header. So from any `## foo-m` it makes `## foo-(n+1)`.
---@return nil
function M.append_global_header()
  local lines  = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local heads  = scan_headings(lines)

  -- The header the cursor sits in: the last heading at or before the cursor.
  local cur_idx
  for i, h in ipairs(heads) do
    if h.lnum <= cursor then cur_idx = i else break end
  end
  if not cur_idx then
    vim.notify('[pkm] put the cursor in a header section first', vim.log.levels.WARN)
    return
  end

  local level = heads[cur_idx].level
  local prefix, num_str, suffix = lines[heads[cur_idx].lnum]:match('^(.*)%-(%d+)(%D*)$')
  if not prefix then
    vim.notify('[pkm] the current header has no -N counter to continue', vim.log.levels.WARN)
    return
  end

  -- Block bounds: from just after the nearest shallower header before the cursor
  -- to the nearest shallower header after it (or EOF). Siblings live in between.
  local block_end = #lines + 1
  for i = cur_idx + 1, #heads do
    if heads[i].level < level then block_end = heads[i].lnum; break end
  end
  local block_start = 1
  for i = cur_idx - 1, 1, -1 do
    if heads[i].level < level then block_start = heads[i].lnum + 1; break end
  end

  -- Highest counter among the same-level, same-prefix siblings in the block.
  local pat  = '^' .. vim.pesc(prefix) .. '%-(%d+)%D*$'
  local maxn = tonumber(num_str)
  for _, h in ipairs(heads) do
    if h.level == level and h.lnum >= block_start and h.lnum < block_end then
      local n = tonumber(lines[h.lnum]:match(pat))
      if n and n > maxn then maxn = n end
    end
  end

  local new_header = prefix .. '-' .. tostring(maxn + 1) .. suffix

  -- Insert just before the block's end (or at EOF); blank separators that do
  -- not double up on an already-blank line.
  local ins0   = block_end - 1
  local before = (block_end - 1 >= 1) and lines[block_end - 1] or ''
  local chunk  = {}
  if before ~= '' then chunk[#chunk + 1] = '' end
  chunk[#chunk + 1] = new_header
  if block_end <= #lines then chunk[#chunk + 1] = '' end

  vim.api.nvim_buf_set_lines(0, ins0, ins0, false, chunk)
  vim.api.nvim_win_set_cursor(0, { ins0 + ((before ~= '') and 2 or 1), 0 })
end

--- Line number of the heading `count` jumps away from `cursor`, or nil.
--- Pure: no buffer access, no window access, no state.
---
--- When fewer than `count` headings remain in that direction the furthest one
--- is returned — a count that overshoots lands on the last heading rather than
--- refusing to move. nil means there is no heading at all that way.
---@param lines  string[]      Buffer lines, 1-indexed
---@param cursor integer       Current line, 1-indexed; the line itself never matches
---@param opts   table|nil     { dir = 'next'|'prev', count = integer, level = integer|'same' }
---                            level: nil = any; 1-6 = only that level; 'same' = the
---                            level of the heading the cursor sits under (any, if none)
---@return integer|nil
function M.find_heading_target(lines, cursor, opts)
  opts = opts or {}
  lines = lines or {}

  local dir   = (opts.dir == 'prev') and 'prev' or 'next'
  local count = math.max(1, math.floor(tonumber(opts.count) or 1))
  local heads = scan_headings(lines)
  if #heads == 0 then return nil end

  local level = tonumber(opts.level)
  if opts.level == 'same' then
    -- The enclosing heading — the last one at or before the cursor.
    for _, h in ipairs(heads) do
      if h.lnum <= cursor then level = h.level else break end
    end
  end

  local function matches(h)
    return (level == nil or h.level == level)
  end

  local found, seen = nil, 0

  if dir == 'next' then
    for _, h in ipairs(heads) do
      if h.lnum > cursor and matches(h) then
        found, seen = h.lnum, seen + 1
        if seen == count then break end
      end
    end
  else
    for i = #heads, 1, -1 do
      local h = heads[i]
      if h.lnum < cursor and matches(h) then
        found, seen = h.lnum, seen + 1
        if seen == count then break end
      end
    end
  end

  return found
end

--- Move the cursor to the heading `find_heading_target` picks.
--- Silent at the boundary — a motion that cannot move is not an error — but
--- says so when the buffer holds no heading at all, which is the case a user
--- would otherwise read as the command being broken.
---@param opts table|nil  Same shape as find_heading_target's opts
---@return boolean  true when the cursor moved
function M.goto_heading(opts)
  opts = opts or {}

  local win    = vim.api.nvim_get_current_win()
  local lines  = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(win)[1]
  local target = M.find_heading_target(lines, cursor, opts)

  if not target then
    if not M.find_heading_target(lines, 0, { dir = 'next' }) then
      vim.notify('[pkm] no headers in this buffer', vim.log.levels.WARN)
    end
    return false
  end

  -- Jumplist entry so <C-o> comes back. Normal mode only: `m` is not a
  -- Visual-mode command, and the mapping runs with Visual still active.
  if vim.fn.mode() == 'n' then pcall(vim.cmd, "normal! m'") end

  vim.api.nvim_win_set_cursor(win, { target, (lines[target]:find('#') or 1) - 1 })
  return true
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
---   list (inciso)     BLOCKQUOTE? INDENT R - text      — uppercase roman + ' - ' (legal incisos)
---   list (subalinea)  BLOCKQUOTE? INDENT r. text       — lowercase roman + '.' (legal subalíneas)
---   list (alpha)      BLOCKQUOTE? INDENT a) text       — lowercase letter + ')' (legal alíneas)
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
  -- strip_bq, to_roman, to_alpha, is_valid_roman are module-level (shared with
  -- renumber_legal). ind_depth/eff_depth are specific to this depth-keyed family
  -- renumber and stay local.

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

    -- Legal *inciso* (LC 95/1998): uppercase roman + ' - ' separator (I -, II -).
    -- Uppercase only, and the ' - ' separator distinguishes it from a lowercase-
    -- roman *subalínea* (roman + '.'). Tried after the digit / emphasis / header
    -- families so they win a line they could both match.
    s = rest:match('^%s*[IVXLCDM]+%s+(%-)%s')
     or rest:match('^%s*[IVXLCDM]+%s+(%-)%s*$')
    if s then kind, sep = 'list_inciso', s; break end

    -- Legal *subalínea*: lowercase roman + '.' (i., ii., iii …). Validated as a
    -- canonical roman numeral so ordinary words (civil., mil.) are not mistaken
    -- for markers. Tried BEFORE the alpha family so 'i.' is read as roman i, not
    -- the 9th letter; the alpha family keeps '.' for non-roman letters (a., g.).
    local subr = rest:match('^%s*([ivxlcdm]+)%. ')
              or rest:match('^%s*([ivxlcdm]+)%.%s*$')
    if subr and is_valid_roman(subr) then kind, sep = 'list_subalinea', '.'; break end

    -- Lettered list (legal *alíneas*: a, b, c …). Lowercase letters only, and
    -- tried LAST because `%l` is the most permissive family — a prose line like
    -- "hello. world" could otherwise be misread as a list. Bounded to one or two
    -- letters so it matches alínea labels (a … z, aa …) but not ordinary words.
    -- The lowercase-roman-'.' case is already claimed by the subalínea family
    -- above, so a '.' here is a non-roman letter (a., g.).
    s = rest:match('^%s*%l%l?([.)]) ')
     or rest:match('^%s*%l%l?([.)])%s*$')
    if s then kind, sep = 'list_alpha', s; break end
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

    elseif kind == 'list_inciso' then
      -- Legal inciso: uppercase roman + ' - ' (LC 95/1998); one separator form,
      -- so there is no sep variant to match.
      local ind, _, body = rest:match('^(%s*)([IVXLCDM]+)%s+%-%s+(.*)$')
      if not ind then
        local ind2 = rest:match('^(%s*)[IVXLCDM]+%s+%-%s*$')
        if ind2 then ind, body = ind2, nil end
      end
      if ind then
        local n   = next_count(eff_depth(bq, ind))
        local num = to_roman(n) or tostring(n)
        new_lines[#new_lines + 1] = body ~= nil
          and bq .. ind .. num .. ' - ' .. body
          or  bq .. ind .. num .. ' -'
        changed, replaced = changed + 1, true
      end

    elseif kind == 'list_subalinea' then
      -- Legal subalínea: lowercase roman + '.'; the token is validated so a
      -- continuation or prose line beginning with roman letters (civil.) is
      -- skipped rather than renumbered.
      local ind, tok, body = rest:match('^(%s*)([ivxlcdm]+)%. (.*)$')
      if not (ind and is_valid_roman(tok)) then
        local ind2, tok2 = rest:match('^(%s*)([ivxlcdm]+)%.%s*$')
        if ind2 and is_valid_roman(tok2) then ind, body = ind2, nil else ind = nil end
      end
      if ind then
        local n   = next_count(eff_depth(bq, ind))
        local num = (to_roman(n) or tostring(n)):lower()
        new_lines[#new_lines + 1] = body ~= nil
          and bq .. ind .. num .. '. ' .. body
          or  bq .. ind .. num .. '.'
        changed, replaced = changed + 1, true
      end

    elseif kind == 'list_alpha' then
      -- Bounded to one or two letters (matching the family detection) so a
      -- mid-range prose line like "word) text" is never swept as an item.
      local ind, _, s, body = rest:match('^(%s*)(%l%l?)([.)]) (.*)$')
      if not (ind and s == sep) then
        local ind2, _, s2 = rest:match('^(%s*)(%l%l?)([.)])%s*$')
        if ind2 and s2 == sep then ind, body = ind2, nil end
      end
      if ind then
        local n   = next_count(eff_depth(bq, ind))
        local num = to_alpha(n) or tostring(n)
        new_lines[#new_lines + 1] = body ~= nil
          and bq .. ind .. num .. sep .. ' ' .. body
          or  bq .. ind .. num .. sep
        changed, replaced = changed + 1, true
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
-- SECTION: Legal nested renumber
-- =============================================================================

-- Classify a blockquote-stripped line by its legal marker TYPE, returning the
-- hierarchy level (1 artigo · 2 parágrafo · 3 inciso · 4 alínea · 5 subalínea),
-- the leading indentation, and the body that follows the marker (with a single
-- leading space, so a re-emit is marker .. body). nil for a non-legal line.
local function classify_legal(rest)
  local ind, body
  -- 1 · artigo: "Art. N" (+ optional 'º'); the number is discarded and rebuilt.
  ind, body = rest:match('^(%s*)Art%.%s+%d+(.*)$')
  if ind then return 1, ind, (body:gsub('^º', '')) end
  -- 2 · parágrafo: "§ N" (+ optional 'º'). "Parágrafo único" is left
  --     unclassified — it is the sole §, so there is nothing to renumber.
  ind, body = rest:match('^(%s*)§%s+%d+(.*)$')
  if ind then return 2, ind, (body:gsub('^º', '')) end
  -- 3 · inciso: uppercase roman + ' - '.
  ind, body = rest:match('^(%s*)[IVXLCDM]+%s+%-%s+(.*)$')
  if ind then return 3, ind, ' ' .. body end
  -- 5 · subalínea: lowercase roman + '.', validated (before alínea, so 'i.' is
  --     roman i, not a lettered item).
  local si, tok, sb = rest:match('^(%s*)([ivxlcdm]+)%.%s+(.*)$')
  if si and is_valid_roman(tok) then return 5, si, ' ' .. sb end
  -- 4 · alínea: lowercase letter + ')'.
  ind, body = rest:match('^(%s*)%l%l?%)%s+(.*)$')
  if ind then return 4, ind, ' ' .. body end
  return nil
end

-- The marker string for a legal level at position n.
local function legal_marker(level, n)
  if level == 1 then return 'Art. ' .. legal_ordinal(n) end
  if level == 2 then return '§ ' .. legal_ordinal(n) end
  if level == 3 then return (to_roman(n) or tostring(n)) .. ' -' end
  if level == 4 then return (to_alpha(n) or tostring(n)) .. ')' end
  return (to_roman(n) or tostring(n)):lower() .. '.'   -- level 5, subalínea
end

--- Renumber a Brazilian legal-text block across all five levels in one pass:
--- artigo (Art. Nº/N) → parágrafo (§ Nº/N) → inciso (R -) → alínea (a)) →
--- subalínea (r.). Each line is classified by marker TYPE; a counter is kept per
--- level and every deeper level resets when a shallower one appears, so nesting
--- is correct regardless of indentation (which is preserved, never reflowed).
--- Non-legal lines (prose, headers, blanks) are preserved and do not count.
---@param start_line integer  1-indexed, inclusive
---@param end_line   integer  1-indexed, inclusive
---@return nil
function M.renumber_legal(start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local counters = {}
  local changed = 0
  local new_lines = {}
  for _, line in ipairs(lines) do
    local bq, rest = strip_bq(line)
    local level, ind, body = classify_legal(rest)
    if level then
      counters[level] = (counters[level] or 0) + 1
      for k = level + 1, 5 do counters[k] = nil end
      local rebuilt = bq .. ind .. legal_marker(level, counters[level]) .. body
      new_lines[#new_lines + 1] = rebuilt
      if rebuilt ~= line then changed = changed + 1 end
    else
      new_lines[#new_lines + 1] = line
    end
  end

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, new_lines)
  if changed > 0 then
    vim.notify(
      string.format('[pkm] renumbered %d legal %s', changed,
        changed == 1 and 'item' or 'items'),
      vim.log.levels.INFO)
  end

  -- Re-sync tree-sitter after buffer modification (see renumber_sequence).
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

--- Renumber a range, routing to the nested legal renumber when the range spans
--- **two or more** distinct legal levels (a genuine hierarchy), and to the
--- single-family renumber_sequence otherwise (a flat list — digit, emphasis,
--- header, or a single legal level, which keeps its indentation-based nesting).
---@param start_line integer
---@param end_line   integer
---@return nil
function M.renumber_range(start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local seen, n_levels = {}, 0
  for _, line in ipairs(lines) do
    local _, rest = strip_bq(line)
    local level = classify_legal(rest)
    if level and not seen[level] then
      seen[level] = true
      n_levels = n_levels + 1
    end
  end
  if n_levels >= 2 then
    M.renumber_legal(start_line, end_line)
  else
    M.renumber_sequence(start_line, end_line)
  end
end

-- =============================================================================
-- SECTION: Structure-aware autowrap
-- =============================================================================

-- Greedy word-wrap: the first line fits `first_w` columns, the rest `rest_w`.
-- Words are never split, so a word wider than the column budget overflows.
local function reflow(text, first_w, rest_w)
  local out, cur, width = {}, '', first_w
  for w in text:gmatch('%S+') do
    if cur == '' then
      cur = w
    elseif #cur + 1 + #w <= width then
      cur = cur .. ' ' .. w
    else
      out[#out + 1] = cur
      cur, width = w, rest_w
    end
  end
  if cur ~= '' then out[#out + 1] = cur end
  if #out == 0 then out[1] = '' end
  return out
end

-- Wrap a single fenced-code line, preserving its whitespace. Unlike `reflow`
-- (which collapses runs of spaces), this keeps the line's leading indentation and
-- any internal whitespace, breaking only at a space that fits the width — an
-- over-long token overflows rather than being split (matching the prose wrap).
-- Continuation segments repeat the leading indent; lines are never joined, so the
-- wrap stays idempotent. Code indentation and column alignment therefore survive.
local function wrap_code_line(line, width)
  local ind  = line:match('^(%s*)')
  local body = line:sub(#ind + 1)
  if body == '' then return { line } end
  local avail = math.max(1, width - #ind)
  local segs, cur = {}, ''
  for ws, word in body:gmatch('(%s*)(%S+)') do
    if cur == '' then
      cur = word                                -- first word; drop leading break ws
    elseif #cur + #ws + #word <= avail then
      cur = cur .. ws .. word                   -- keep the internal whitespace run
    else
      segs[#segs + 1] = cur; cur = word         -- break: the break-space is dropped
    end
  end
  if cur ~= '' then segs[#segs + 1] = cur end
  if #segs == 0 then return { line } end
  local out = {}
  for _, s in ipairs(segs) do out[#out + 1] = ind .. s end
  return out
end

-- Marker families recognised by the autowrap, in detection order; each returns
-- (indent, marker, body). Legal markers reuse the same shapes as the renumber.
local WRAP_MARKERS = {
  '^(%s*)(%d+[.)])%s+(.*)$',         -- digit list
  '^(%s*)([%-%*%+])%s+(.*)$',        -- bullet
  '^(%s*)(Art%.%s+%d+º?)%s+(.*)$',   -- artigo
  '^(%s*)(§%s+%d+º?)%s+(.*)$',       -- parágrafo
  '^(%s*)([IVXLCDM]+%s+%-)%s+(.*)$', -- inciso
  '^(%s*)(%l%l?%))%s+(.*)$',         -- alínea
}

--- Detect a list marker at the start of a line. Returns indent, marker, body, or
--- nil for a non-marker line. The subalínea (lowercase roman + '.') is validated
--- as a canonical roman, so `civil.`/`mil.` are treated as prose, not markers.
local function wrap_marker(line)
  for _, pat in ipairs(WRAP_MARKERS) do
    local ind, marker, body = line:match(pat)
    if ind then return ind, marker, body end
  end
  local ind, tok, body = line:match('^(%s*)([ivxlcdm]+)%.%s+(.*)$')
  if ind and is_valid_roman(tok) then return ind, tok .. '.', body end
  return nil
end

-- A line the autowrap must never reflow (and which closes any open block).
-- Fenced-code content is handled separately by the caller (wrapped per line), so
-- this is only reached outside a fence.
local function wrap_structural(line)
  return line:match('^%s*$')             -- blank
      or line:match('^%s*#')             -- ATX header
      or line:match('^%s*|')             -- table row
      or line:match('^%s*%-%-%-+%s*$')   -- frontmatter fence / thematic break
      or line:match('^%s*%*%*%*+%s*$')
      or line:match('^%s*___+%s*$')
end

-- Split a blockquote line into (depth, quoted-text). Depth is the number of `>`
-- markers; the quoted text has its surrounding whitespace trimmed. Returns nil
-- for a non-quote line. Any indentation before the first `>` is dropped — a
-- blockquote is not itself an indented block here.
local function wrap_blockquote(line)
  local prefix, rest = line:match('^%s*(>[>%s]*)(.-)%s*$')
  if not prefix then return nil end
  local _, depth = prefix:gsub('>', '')
  return depth, rest
end

-- The normalised prefix for a blockquote of the given depth: one `>` plus three
-- spaces (a 4-column indent) per level, so quoted text starts at column 4·depth.
local function bq_prefix(depth)
  return ('>   '):rep(depth)
end

--- Reflow a line range to `textwidth` (or 80), list-aware. A list item's
--- continuation lines are re-indented to **marker_indent + 4** — never the marker
--- width (Option A) — with short markers padded to the 4-space tab stop and long
--- markers (`xiii.`, `100.`) overflowing only the first line. Plain paragraphs
--- reflow at their own indent. Blockquotes reflow too, at a normalised `>` + 3
--- spaces (a 4-column indent) per level with the marker repeated on each wrapped
--- line; a quoted list/marker line is re-prefixed but not folded into prose.
--- Fenced-code **content** wraps per line, preserving each line's indentation and
--- internal whitespace (code alignment survives; over-long tokens overflow rather
--- than split), while the ``` fences, headers, tables and frontmatter are left
--- untouched. Idempotent.
---@param start_line integer  1-indexed, inclusive
---@param end_line   integer  1-indexed, inclusive
---@return nil
function M.wrap_range(start_line, end_line)
  local tw = (vim.bo.textwidth and vim.bo.textwidth > 0) and vim.bo.textwidth or 80
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local out, in_fence, blk, bq = {}, false, nil, nil

  local function flush()
    if bq then
      local prefix = bq_prefix(bq.depth)
      local w      = math.max(1, tw - #prefix)
      for _, seg in ipairs(reflow(table.concat(bq.parts, ' '), w, w)) do
        out[#out + 1] = prefix .. seg
      end
      bq = nil
      return
    end
    if not blk then return end
    local body = table.concat(blk.parts, ' ')
    if blk.marker then
      local mi   = #blk.indent
      local pad  = math.max(1, 4 - #blk.marker)
      local fcol = mi + #blk.marker + pad
      local cont = mi + 4
      local segs = reflow(body, math.max(1, tw - fcol), math.max(1, tw - cont))
      out[#out + 1] = blk.indent .. blk.marker .. string.rep(' ', pad) .. segs[1]
      for i = 2, #segs do out[#out + 1] = string.rep(' ', cont) .. segs[i] end
    else
      local base = #blk.indent
      local segs = reflow(body, math.max(1, tw - base), math.max(1, tw - base))
      for _, seg in ipairs(segs) do out[#out + 1] = blk.indent .. seg end
    end
    blk = nil
  end

  for _, line in ipairs(lines) do
    if line:match('^%s*```') or line:match('^%s*~~~') then
      flush(); out[#out + 1] = line; in_fence = not in_fence
    elseif in_fence then
      -- Fenced-code content wraps per line — each line on its own (no joining, no
      -- marker detection), preserving its indentation AND internal whitespace so
      -- code alignment survives; the ``` fences themselves are left untouched.
      flush()
      if line:match('^%s*$') then
        out[#out + 1] = line
      else
        for _, seg in ipairs(wrap_code_line(line, tw)) do
          out[#out + 1] = seg
        end
      end
    elseif line:match('^%s*>') then
      local depth, rest = wrap_blockquote(line)
      if rest == '' then
        -- Bare `>` line: a paragraph break inside the quote. Emit the marker(s)
        -- with trailing padding trimmed, and end the current quote paragraph.
        flush(); out[#out + 1] = (bq_prefix(depth):gsub('%s+$', ''))
      elseif wrap_marker(rest) then
        -- A quoted list/marker line: re-prefix it but do not fold it into prose
        -- (reflowing structured content inside a quote is not done here).
        flush(); out[#out + 1] = bq_prefix(depth) .. rest
      elseif bq and bq.depth == depth then
        bq.parts[#bq.parts + 1] = rest        -- lazy continuation, same depth
      else
        flush(); bq = { depth = depth, parts = { rest } }
      end
    elseif wrap_structural(line) then
      flush(); out[#out + 1] = line
    else
      if bq then flush() end   -- a non-quote line ends any open blockquote
      local ind, marker, body = wrap_marker(line)
      if marker then
        flush()
        blk = { indent = ind, marker = marker, parts = { body } }
      elseif blk then
        blk.parts[#blk.parts + 1] = vim.trim(line)   -- lazy continuation
      else
        blk = { indent = line:match('^(%s*)'), marker = nil, parts = { vim.trim(line) } }
      end
    end
  end
  flush()

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, out)
end

--- Reflow the paragraph surrounding the cursor (blank-line bounded).
---@return nil
function M.wrap_at_cursor()
  local s, e = paragraph_bounds()
  M.wrap_range(s, e)
end

--- 'formatexpr' hook: routes `gq`/`gw` (and any motion — `gqq`, `gq3j`, `gqap`,
--- visual `gq`) through the structure-aware wrap. Set as the buffer's formatexpr
--- on PKM notes, so the author's existing gq muscle memory just works. Falls back
--- to Neovim's internal formatter for insert-mode auto-wrap (`fo` t/a), which
--- passes one line at a time and expects character-level behaviour.
---@return integer  0 = handled, 1 = fall back to the internal formatter
function M.formatexpr()
  if vim.fn.mode():match('[iR]') then return 1 end
  local lnum  = vim.v.lnum
  local count = math.max(vim.v.count, 1)
  M.wrap_range(lnum, lnum + count - 1)
  return 0
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

  -- strip_bq is module-level (SECTION: Shared numbering helpers).

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
