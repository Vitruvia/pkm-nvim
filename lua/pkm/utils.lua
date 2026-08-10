-- =============================================================================
-- pkm.utils — Shared cross-platform utilities
-- =============================================================================
-- Dependencies : none
-- Consumed by  : all pkm modules
--
-- No setup() needed — require and use directly.
-- All path operations use M.sep so they work on Windows, WSL, and Linux.
--
-- Public values:
--   is_windows (boolean)  true on win32/win64
--   is_wsl     (boolean)  true in WSL environment
--   sep        (string)   platform path separator ("\" or "/")
--
-- Public API:
--   join(...)             → platform-joined path string
--   normalize(path)       → path with correct separators for current OS
--   read_lines(path)      → string[]|nil, readfile-equivalent, LuaJIT-only I/O
--   ensure_dir(path)      → create directory recursively if absent
--   notify(msg, level?)   → vim.notify with "[pkm] " prefix
--   type_prefix(nt)       → compact bracketed note-type label, e.g. "[n]"
--   strip_display_prefix(filename, nt) → stem without number/type prefix
--   is_editing_win(win)   → boolean, a window a note may be opened in
--   editing_wins()        → those windows, left to right
--   focus_editing_win(where?) → move there (or split / window N), creating one
--                               if the tabpage has none
-- =============================================================================

local M = {}

-- OS flags (evaluated once at load time)
M.is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
M.is_wsl     = vim.fn.has('wsl') == 1

-- Platform path separator
M.sep = package.config:sub(1, 1)

--- Join path components with the platform separator.
---@param ... string Path components
---@return string
function M.join(...)
  return table.concat({...}, M.sep)
end

--- Normalize path separators for the current platform.
--- On Windows: converts / to \
--- On Unix:    converts \ to /
---@param path string
---@return string
function M.normalize(path)
  if M.is_windows then
    return path:gsub("/", "\\")
  else
    return path:gsub("\\", "/")
  end
end

--- Read a file into an array of lines, reproducing `vim.fn.readfile()`'s
--- normalisation exactly while staying inside LuaJIT: a leading UTF-8 BOM is
--- dropped, `\n` separates lines, a CR immediately before an LF is removed (a
--- trailing CR at end-of-file, with no LF after it, is kept — `readfile` keeps
--- it too), and an empty file yields an empty array.
---
--- Measured at ~0.55× the cost of `vim.fn.readfile` over 600 notes, the VimL
--- round trip being what it avoids. Used by the index build; prefer
--- `vim.fn.readfile` in interactive paths where one file is read at a time and
--- the difference is invisible.
---@param path string  Absolute path to read
---@return string[]|nil lines  nil when the file cannot be opened
function M.read_lines(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local data = f:read('*a')
  f:close()
  if not data or data == '' then return {} end
  if data:sub(1, 3) == '\239\187\191' then data = data:sub(4) end

  local lines, pos, len = {}, 1, #data
  while pos <= len do
    local nl = data:find('\n', pos, true)
    if nl then
      local line = data:sub(pos, nl - 1)
      if line:sub(-1) == '\r' then line = line:sub(1, -2) end
      lines[#lines + 1] = line
      pos = nl + 1
    else
      lines[#lines + 1] = data:sub(pos)
      pos = len + 1
    end
  end
  return lines
end

--- Ensure a directory exists, creating it recursively if needed.
---@param path string
---@return boolean success
function M.ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    return vim.fn.mkdir(path, "p") == 1
  end
  return true
end

--- Emit a PKM-prefixed notification.
---@param msg string
---@param level integer? vim.log.levels constant (default: WARN)
function M.notify(msg, level)
  vim.notify("[pkm] " .. msg, level or vim.log.levels.WARN)
end

-- Note-type single-letter abbreviations for compact display prefixes.
-- Superset of every note_type used across panels/pickers; unknown types
-- fall back to 'o'.
local TYPE_ABBREV = {
  note    = 'n',
  agg     = 'a',
  bib     = 'b',
  journal = 'j',
  scratch = 's',
  other   = 'o',
  file    = 'f',
}

--- Format a note type as a compact bracketed label for display alignment.
---@param note_type string|nil
---@return string  e.g. "[n]" or "[j]"
function M.type_prefix(note_type)
  return '[' .. (TYPE_ABBREV[note_type or 'other'] or 'o') .. ']'
end

--- Strip the leading note-number and type prefix from a filename stem.
--- "0042_note_Title_Words"     → "Title_Words"
--- "journal_2026-06-17_10-30"  → "2026-06-17_10-30"
--- Unknown conventions: returned unchanged.
---@param filename  string  Index `filename` field (stem, no extension)
---@param note_type string
---@return string
function M.strip_display_prefix(filename, note_type)
  if note_type == 'journal' or note_type == 'scratch' then
    return filename:match('^%a+_(.+)$') or filename
  elseif note_type == 'note' or note_type == 'agg' or note_type == 'bib' then
    return filename:match('^%d+_%a+_(.+)$') or filename
  end
  return filename
end

--- Build the winbar text for a note row in a panel: "title · filename", where
--- `filename` is the raw stem *including* the note number. Panels strip the
--- number from their row labels, so the winbar is the one place it stays
--- readable; the title rides alongside it, space permitting. Falls back to the
--- stem alone when there is no distinct title. A leading space insets it from
--- the window edge, and `%` is doubled so the winbar mini-language treats it
--- as a literal.
---@param entry table|nil  index entry (for its `title`), or nil
---@param path  string     absolute note path
---@return string  winbar value (already `%`-escaped)
function M.winbar_label(entry, path)
  local stem  = vim.fn.fnamemodify(path, ':t:r')
  local title = entry and entry.title
  local text
  if title and title ~= '' and title ~= stem then
    text = title .. '  ·  ' .. stem
  else
    text = stem
  end
  return ' ' .. (text:gsub('%%', '%%%%'))
end

-- =============================================================================
-- SECTION: Editing windows
-- =============================================================================
--
-- PKM's panels set `winfixbuf`, which turns "open a file from here" into a hard
-- error (E1513) rather than a hijacked panel. That is the intended trade, but it
-- means anything that opens a buffer must first move to a window that may hold
-- one. Two copies of that search already existed — one in `commands`, one in
-- `views` — so it lives here now, where both can reach it.

local PANEL_FILETYPES = {
  ['pkm-sidebar']  = true,
  ['pkm-bufpanel'] = true,
  ['netrw']        = true,
}

--- Is this window one a note may be opened in?
--- Floats and PKM's own panels are not.
---@param win integer
---@return boolean
function M.is_editing_win(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  if vim.api.nvim_win_get_config(win).relative ~= '' then return false end
  return not PANEL_FILETYPES[vim.bo[vim.api.nvim_win_get_buf(win)].filetype]
end

--- Every window in this tabpage a note may be opened in, left to right.
--- The order is what gives `[count]` its meaning: 1 is the leftmost.
---@return integer[] wins
function M.editing_wins()
  local found = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if M.is_editing_win(win) then
      found[#found + 1] = { win = win, col = vim.api.nvim_win_get_position(win)[2] }
    end
  end
  table.sort(found, function(a, b) return a.col < b.col end)

  local wins = {}
  for i, entry in ipairs(found) do wins[i] = entry.win end
  return wins
end

--- Run a window-creating command, resilient to E36 "Not enough room".
--- The PKM panels are `winfixheight` / `winfixwidth`, so once the user closes
--- every editing window (e.g. `:quit` with the sidebar + buffer panel open) a
--- split from a panel can find no room to take and Vim raises E36 — which is the
--- crash the buffer bar's `<CR>` hit. On failure, drop the fixed sizes across the
--- tabpage so the split can reclaim space, retry, then restore the flags on the
--- windows that survive (the panels re-assert their own height on next refresh).
---@param cmd string  a :split / :vsplit / :new / … command
---@return boolean ok  whether a window was created
function M.win_create_resilient(cmd)
  if pcall(vim.cmd, cmd) then return true end

  local saved = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(w) then
      saved[w] = { vim.wo[w].winfixheight, vim.wo[w].winfixwidth }
      vim.wo[w].winfixheight = false
      vim.wo[w].winfixwidth  = false
    end
  end

  local ok = pcall(vim.cmd, cmd)

  for w, f in pairs(saved) do
    if vim.api.nvim_win_is_valid(w) then
      vim.wo[w].winfixheight = f[1]
      vim.wo[w].winfixwidth  = f[2]
    end
  end
  return ok
end

--- Move the cursor to a window a note may be opened in, creating one if the
--- tabpage has none, and return it.
---
--- `where` says *which*:
---   nil / 'current'  the current window when it already qualifies, else the
---                    alternate one, else the leftmost — "where I was working"
---   'left','right'   a new vertical split on that side of the above
---   integer N        the Nth editing window, counted from the left; falls back
---                    to the default and reports when there is no such window,
---                    rather than silently rearranging the layout
---
--- When nothing qualifies, the new window is placed against the panel we are
--- leaving: beside a sidebar (a left split), above a buffer panel (a bottom
--- one), so the result is where the eye expects it either way.
---@param where nil|'current'|'left'|'right'|integer
---@return integer win
function M.focus_editing_win(where)
  local cur = vim.api.nvim_get_current_win()

  local function base()
    if M.is_editing_win(cur) then return cur end

    local alt = vim.fn.win_getid(vim.fn.winnr('#'))
    if alt ~= 0 and alt ~= cur and M.is_editing_win(alt) then return alt end

    local wins = M.editing_wins()
    if wins[1] then return wins[1] end

    -- None at all: make one, on the side that suits the panel we are in.
    local from_bufpanel = vim.bo[vim.api.nvim_win_get_buf(cur)].filetype == 'pkm-bufpanel'
    M.win_create_resilient(from_bufpanel and 'noautocmd aboveleft split'
                                          or 'noautocmd rightbelow vsplit')
    return vim.api.nvim_get_current_win()
  end

  if type(where) == 'number' then
    local wins = M.editing_wins()
    if wins[where] then
      vim.api.nvim_set_current_win(wins[where])
      return wins[where]
    end
    M.notify(string.format('no window %d (only %d editing window%s) — using the usual one',
      where, #wins, #wins == 1 and '' or 's'), vim.log.levels.WARN)
    where = nil
  end

  local win = base()
  vim.api.nvim_set_current_win(win)

  if where == 'left' or where == 'right' then
    M.win_create_resilient(where == 'left' and 'noautocmd leftabove vsplit'
                                            or 'noautocmd rightbelow vsplit')
    win = vim.api.nvim_get_current_win()
  end

  return win
end

return M
