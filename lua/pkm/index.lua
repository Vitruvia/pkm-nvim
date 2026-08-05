-- =============================================================================
-- pkm.index — In-memory note index with incremental invalidation
-- =============================================================================
-- Dependencies : pkm.utils (join, read_lines), libuv (vim.uv), pkm.yaml (lazy)
-- Consumed by  : pkm.export (collect_files), pkm.views, pkm.bench (run_suite)
--
-- Eliminates the per-query readfile + parse_frontmatter scan by caching all
-- note data in a Lua table. The index is built lazily on the first call to
-- get_all() and kept current by invalidating one entry per BufWritePost.
--
-- Index entry shape:
--   index[path] = {
--     path          : string   absolute path (duplicated for convenience)
--     filename      : string   file stem without extension
--     note_type     : string   'note' | 'agg' | 'bib' | 'journal' | 'scratch' | 'other'
--     title         : string   frontmatter title if non-empty; filename stem with _ → space
--     tags          : string[] frontmatter tags, lowercased, or {}
--     body          : string   note body (lines after frontmatter joined with "\n")
--     mtime         : number   vim.fn.getftime() at last index time
--     has_citations : boolean  true when cites or cited_by has ≥1 entry in any group
--     body_lower    : string   lowercased body, cached to avoid recomputing
--                               :lower() on every filter.eval() call
--   }
--
-- Thread-safety: Neovim Lua is single-threaded; no locking needed.
--
-- The build is lazy (first get_all/get) unless start_background_build() has
-- warmed it in chunks after startup (gated by pkm_mode.index.prebuild), which
-- keeps the first sidebar/pop-up open off the cold scan.
--
-- Public API:
--   setup(config)             → store config; register BufWritePost autocmd;
--                               schedule the background warm-up build
--   get_all()                 → index_entry[]  (builds on first call if cold)
--   get(path)                 → index_entry | nil
--   start_background_build()  → warm the index in idle chunks; no-op if built
--   invalidate(path)          → re-read one file; remove entry if file gone
--   rebuild()                 → full rescan; call after bulk external changes
--   is_built()                → boolean (true only when fully built)
-- =============================================================================

local M = {}

local utils = require('pkm.utils')
local uv    = vim.uv or vim.loop

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

-- Background (chunked) build state. When a background build is running, the
-- full file list lives in _bg_queue and _bg_pos is the next index to read; the
-- index is populated a slice at a time on the event loop so it never freezes.
-- Any caller that needs a complete index before it finishes drains the rest
-- synchronously (ensure_built → bg_finish_sync). See start_background_build().
local _bg_queue  = nil    -- string[] of all note paths during a bg build, else nil
local _bg_pos    = 1      -- 1-based cursor into _bg_queue
local _bg_active = false  -- true while a chunked background build is in progress
local BG_CHUNK   = 400    -- files read per idle slice
local BG_DELAY   = 8      -- ms yielded to the UI between slices

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

  -- Warm the index in the background shortly after startup so the first
  -- sidebar / pop-up / browse open is not the cold synchronous scan. Chunked,
  -- so it never freezes; a panel opened before it finishes completes the
  -- remainder synchronously (ensure_built). Gated by pkm_mode.index.prebuild.
  local pm = user_config.pkm_mode
  if pm and pm.index and pm.index.prebuild then
    vim.defer_fn(function() M.start_background_build() end, 200)
  end
end

-- =============================================================================
-- SECTION: Internal helpers
-- =============================================================================
--
--- Classify a note's type from its filename stem.
---@param stem string
---@return string  'note' | 'agg' | 'bib' | 'journal' | 'scratch' | 'other'
local function get_note_type(stem)
  if stem:match('^scratch_') then return 'scratch' end
  if stem:match('^journal_') then return 'journal' end
  local t = stem:match('^%d+_([a-z]+)_')
  if t == 'note' or t == 'agg' or t == 'bib' then return t end
  return 'other'
end

--- Read one file and return an index entry, or nil if unreadable/no frontmatter.
---@param path string  Absolute path to a .md note file
---@return table|nil entry
local function read_entry(path)

  local lines = utils.read_lines(path)
  if type(lines) ~= 'table' or #lines == 0 then return nil end

  local yaml = require('pkm.yaml')
  local fm, content_start = yaml.parse_frontmatter(lines)
  if not fm then return nil end

  -- File stem used for the filename: predicate and as the title fallback.
  local filename = vim.fn.fnamemodify(path, ':t:r')
  local note_type = get_note_type(filename)

  -- Title: free-form frontmatter field if present and non-empty;
  -- otherwise derive from the filename stem.
  local title
  if type(fm.title) == 'string' and fm.title ~= '' then
    title = fm.title
  else
    title = filename:gsub('_', ' ')
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

  -- Detect whether the note has any frontmatter citations (cites or cited_by).
  local has_cites = false
  local function any_in_groups(tbl)
    if type(tbl) ~= 'table' then return false end
    for _, grp in ipairs({ 'notes', 'bib', 'journal', 'scratch' }) do
      if type(tbl[grp]) == 'table' and #tbl[grp] > 0 then return true end
    end
    return false
  end
  if any_in_groups(fm.cites) or any_in_groups(fm.cited_by) then
    has_cites = true
  end

  -- Body: lines from content_start onward joined with newline.
  -- content_start is 1-based; lines is 1-based.
  local body_parts = {}
  if content_start and content_start <= #lines then
    for i = content_start, #lines do
      body_parts[#body_parts + 1] = lines[i]
    end
  end

  local body = table.concat(body_parts, '\n')
  return {
    path       = path,
    filename   = filename,
    note_type  = note_type,
    title      = title,
    tags       = tags,
    body       = body,
    body_lower = body:lower(),
    mtime      = vim.fn.getftime(path),
    has_citations = has_cites,
  }
end

-- Windows and WSL's drive mounts are case-insensitive, so the vim.fn.glob()
-- this listing replaced also matched NOTE.MD there; on Linux it did not.
-- Matching that per platform keeps the indexed set identical to before.
local _ext_ci = utils.is_windows or utils.is_wsl

--- True when name ends in the .md extension, per the platform's case rules.
---@param name string
---@return boolean
local function has_md_ext(name)
  local ext = name:sub(-3)
  return ext == '.md' or (_ext_ci and ext:lower() == '.md')
end

--- Return all .md files directly under dir as an array of absolute paths.
---
--- One libuv directory read instead of `vim.fn.glob`: measured at 0.6 ms vs
--- 107 ms for 600 files (~167×), the difference being VimL wildcard expansion.
--- Two deliberate consequences of dropping glob: the order is now whatever the
--- filesystem returns (build() stores entries in a hash keyed by path, and
--- get_all() already iterated unordered, so nothing depends on it), and
--- 'wildignore'/'suffixes' no longer hide note files from the index.
---@param dir string
---@return string[]
local function glob_md(dir)
  local req = uv.fs_scandir(dir)
  if not req then return {} end   -- absent, unreadable, or not a directory

  local files = {}
  while true do
    local name, typ = uv.fs_scandir_next(req)
    if not name then break end
    if typ ~= 'directory' and has_md_ext(name) then
      files[#files + 1] = utils.join(dir, name)
    end
  end
  return files
end

-- =============================================================================
-- SECTION: Build
-- =============================================================================

--- List every note path under the configured folders — the cheap part of a
--- build (one libuv scandir per folder, no file reads).
---@return string[]  absolute paths
local function collect_files()
  local files = {}
  local folders = {
    _config.folders.consolidated,
    _config.folders.journal,
    _config.folders.scratchpad,
  }
  for _, folder in ipairs(folders) do
    for _, path in ipairs(glob_md(utils.join(_config.root_path, folder))) do
      files[#files + 1] = path
    end
  end
  return files
end

--- Perform a full synchronous scan of all note folders and populate _index.
local function build()
  if not _config then
    vim.notify('PKMIndex: setup() not called before build()', vim.log.levels.ERROR)
    return
  end
  _index = {}
  for _, path in ipairs(collect_files()) do
    local entry = read_entry(path)
    if entry then _index[norm(path)] = entry end
  end
  _built = true
end

-- Drain the remainder of an in-progress background build synchronously, then
-- finalize. Called when a caller needs a complete index before the chunked
-- build has finished — it pays only for the files not yet read, never the whole
-- corpus. A still-pending bg_step() then sees _bg_active=false and no-ops.
local function bg_finish_sync()
  if _bg_queue then
    for i = _bg_pos, #_bg_queue do
      local entry = read_entry(_bg_queue[i])
      if entry then _index[norm(_bg_queue[i])] = entry end
    end
  end
  _bg_queue, _bg_pos, _bg_active = nil, 1, false
  _built = true
end

-- Read one slice of the background queue, then reschedule until it is drained.
-- Runs on the main loop (vim.defer_fn), so read_entry's vim.fn.* calls are
-- legal. Guards against a superseding finish_sync/rebuild.
local function bg_step()
  if not _bg_active or not _bg_queue then return end
  local q    = _bg_queue
  local stop = math.min(_bg_pos + BG_CHUNK - 1, #q)
  for i = _bg_pos, stop do
    local entry = read_entry(q[i])
    if entry then _index[norm(q[i])] = entry end
  end
  _bg_pos = stop + 1
  if _bg_pos > #q then
    _bg_queue, _bg_pos, _bg_active = nil, 1, false
    _built = true
  else
    vim.defer_fn(bg_step, BG_DELAY)
  end
end

--- Kick off a chunked background build so the first interactive index access
--- (sidebar / pop-up / browse) is warm instead of paying the cold scan. No-op
--- if the index is already built or a background build is already running.
--- The file list is gathered up front (cheap); files are read a slice at a time
--- on the event loop. If get_all()/get() is called before it finishes, the rest
--- is read synchronously then, so callers never see a partial index. Idempotent.
function M.start_background_build()
  if _built or _bg_active or not _config then return end
  _index    = {}
  _bg_queue = collect_files()
  _bg_pos   = 1
  if #_bg_queue == 0 then
    _bg_queue, _built = nil, true
    return
  end
  _bg_active = true
  vim.defer_fn(bg_step, BG_DELAY)
end

-- Ensure a complete index exists: return if built, finish an in-progress
-- background build synchronously, else do a full synchronous build.
local function ensure_built()
  if _built then return end
  if _bg_active then bg_finish_sync() else build() end
end

-- =============================================================================
-- SECTION: Public API
-- =============================================================================

--- Return all index entries as a flat array.
--- Builds the index on the first call; subsequent calls are O(n) table iteration.
---@return table[]  Array of index entry tables
function M.get_all()
  ensure_built()

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
  ensure_built()
  return _index[norm(path)]
end

--- Scan an arbitrary vault root and return its note entries, **without** building
--- or touching the active singleton index. It reuses the same per-file reader as
--- build(), so the entries match get_all()'s shape exactly. This is the
--- non-disruptive seam for cross-vault reads (e.g. `pkm.api.find_all`): searching
--- another vault must neither switch the active root nor rebuild the live index,
--- and this reads straight from that root's files instead.
---@param root string  Absolute vault root to scan
---@param folders string[]|nil  Folder names under root (default: the configured note folders)
---@return table[] entries
function M.scan_root(root, folders)
  if type(root) ~= 'string' or root == '' or not _config then return {} end
  folders = folders or {
    _config.folders.consolidated,
    _config.folders.journal,
    _config.folders.scratchpad,
  }
  local out = {}
  for _, folder in ipairs(folders) do
    for _, path in ipairs(glob_md(utils.join(root, folder))) do
      local entry = read_entry(path)
      if entry then out[#out + 1] = entry end
    end
  end
  return out
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
  -- Cancel any in-progress background build (a pending bg_step no-ops).
  _bg_queue, _bg_pos, _bg_active = nil, 1, false
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
