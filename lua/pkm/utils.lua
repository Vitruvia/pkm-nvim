-- lua/pkm/utils.lua
-- Shared cross-platform utilities.
-- No setup() needed — require and use directly.

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
  vim.notify("[PKM] " .. msg, level or vim.log.levels.WARN)
end

return M
