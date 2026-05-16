-- =============================================================================
-- pkm.index — In-memory note index with incremental invalidation
-- =============================================================================
-- Dependencies : pkm.utils, pkm.yaml (lazy)
-- Consumed by  : pkm.export (collect_files), pkm.views (planned),
--                pkm.bench (run_suite)
--
-- Eliminates the per-query readfile + parse_frontmatter scan by caching all
-- note data in a Lua table. The index is built lazily on the first call to
-- get_all() and kept current by invalidating one entry per BufWritePost.
--
-- Index entry shape:
--   index[path] = {
--     path  : string    absolute path (duplicated for convenience)
--     title : string    frontmatter title, or "" if absent
--     tags  : string[]  frontmatter tags array, or {}
--     body  : string    note body (lines after frontmatter joined with "\n")
--     mtime : number    vim.fn.getftime() at last index time
--   }
--
-- Thread-safety: Neovim Lua is single-threaded; no locking needed.
--
-- Public API:
--   setup(config)          → store config reference; register BufWritePost autocmd
--   get_all()              → index_entry[]  (builds index on first call)
--   get(path)              → index_entry | nil
--   invalidate(path)       → re-read one file; remove entry if file gone
--   rebuild()              → full rescan; call after bulk external changes
--   is_built()             → boolean
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: State
-- =============================================================================
-- Normalize path separators for cross-platform key lookup.
local function norm(p)
  return p:gsub('\\', '/')

end
local _index  = {}      -- path → entry table
local _built  = false   -- true after first full scan
local _config = nil     -- set by setup()

-- =============================================================================
-- SECTION: Setup
-- =============================================================================

--- Initialise the index module and register the BufWritePost autocmd that
--- invalidates one entry every time a PKM note is saved.
--- Must be called from pkm.init.setup() after config is resolved.
---@param user_config table Resolved PKM config from pkm.config.resolve()
function M.setup(user_config)
  _config = user_config

  local augroup = vim.api.nvim_create_augroup('PKMIndex', { clear = true })

  vim.api.nvim_create_autocmd('BufWritePost', {
    group   = augroup,
    pattern = '*.md',
    callback = function()
      if not _built then return end   -- index not yet built; nothing to maintain

      local filepath = vim.fn.expand('<afile>:p')
      local root     = _config.root_path

      -- Only invalidate files inside the PKM root.
      local norm_file = filepath:gsub('\\', '/')
      local norm_root = root:gsub('\\', '/')
      if not norm_file:lower():find(norm_root:lower(), 1, true) then return end

      M.invalidate(filepath)
    end,
  })
end

-- =============================================================================
-- SECTION: Internal helpers
-- =============================================================================

--- Read one file and return an index entry, or nil if unreadable/no frontmatter.
---@param path string  Absolute path to a .md note file
---@return table|nil entry
local function read_entry(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' or #lines == 0 then return nil end

  local yaml = require('pkm.yaml')
  local fm, content_start = yaml.parse_frontmatter(lines)
  if not fm then return nil end

  -- Extract title (string or empty).
  local title = ''
  if type(fm.title) == 'string' then
    title = fm.title
  end

  -- Normalise tags to a flat array of lowercase strings.
  local tags = {}
  if type(fm.tags) == 'table' then
    for _, t in ipairs(fm.tags) do
      if type(t) == 'string' then
        tags[#tags + 1] = t:lower()
      end
    end
  end

  -- Body: lines from content_start onward joined with newline.
  -- content_start is 1-based; lines is 1-based.
  local body_parts = {}
  if content_start and content_start <= #lines then
    for i = content_start, #lines do
      body_parts[#body_parts + 1] = lines[i]
    end
  end

  return {
    path  = path,
    title = title,
    tags  = tags,
    body  = table.concat(body_parts, '\n'),
    mtime = vim.fn.getftime(path),
  }
end

--- Return all .md files under dir as an array of absolute paths.
---@param dir string
---@return string[]
local function glob_md(dir)
  if vim.fn.isdirectory(dir) ~= 1 then return {} end
  local files = vim.fn.glob(dir .. utils.sep .. '*.md', false, true)
  return type(files) == 'table' and files or {}
end

-- =============================================================================
-- SECTION: Build
-- =============================================================================

--- Perform a full scan of all note folders and populate _index.
--- Called automatically by get_all() on the first invocation.
local function build()
  if not _config then
    vim.notify('PKMIndex: setup() not called before build()', vim.log.levels.ERROR)
    return
  end

  _index = {}

  local folders = {
    _config.folders.consolidated,
    _config.folders.journal,
    _config.folders.scratchpad,
  }

  for _, folder in ipairs(folders) do
    local dir = utils.join(_config.root_path, folder)
    for _, path in ipairs(glob_md(dir)) do
      local entry = read_entry(path)
      if entry then
        _index[norm(path)] = entry
      end
    end
  end

  _built = true
end

-- =============================================================================
-- SECTION: Public API
-- =============================================================================

--- Return all index entries as a flat array.
--- Builds the index on the first call; subsequent calls are O(n) table iteration.
---@return table[]  Array of index entry tables
function M.get_all()
  if not _built then build() end

  local out = {}
  for _, entry in pairs(_index) do
    out[#out + 1] = entry
  end
  return out
end

--- Return the index entry for a single path, or nil if not indexed.
--- Builds the index on the first call.
---@param path string  Absolute path
---@return table|nil entry
function M.get(path)
  if not _built then build() end
  return _index[norm(path)]
end

--- Re-read one file and update its index entry.
--- If the file no longer exists, its entry is removed.
--- Called automatically by the BufWritePost autocmd.
---@param path string  Absolute path
function M.invalidate(path)
  local key = norm(path)
  if vim.fn.filereadable(path) == 0 then
    _index[key] = nil
    return
  end
  local entry = read_entry(path)
  if entry then
    _index[key] = entry
  else
    _index[key] = nil
  end
end

--- Discard the current index and rebuild from scratch.
--- Use after bulk external changes (e.g. a git pull that touches many files).
function M.rebuild()
  _built = false
  build()
  vim.notify(
    string.format('PKMIndex: rebuilt — %d notes indexed', vim.tbl_count(_index)),
    vim.log.levels.INFO)
end

--- Return true if the index has been built at least once.
---@return boolean
function M.is_built()
  return _built
end

return M
