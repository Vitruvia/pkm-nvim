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
--   ensure_dir(path)      → create directory recursively if absent
--   notify(msg, level?)   → vim.notify with "[pkm] " prefix
--   type_prefix(nt)       → compact bracketed note-type label, e.g. "[n]"
--   strip_display_prefix(filename, nt) → stem without number/type prefix
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

return M
