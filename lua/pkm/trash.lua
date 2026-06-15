-- =============================================================================
-- pkm.trash — Soft-delete (trash) for PKM notes
-- =============================================================================
-- Dependencies : pkm.index (lazy), pkm.citations (lazy), pkm.utils
-- Consumed by  : pkm.init (delete_note_safely),
--                pkm.commands (:PKMRestoreNote, :PKMEmptyTrash)
--                pkm.notes (get_next_note_number — reads manifest for numbering)
--
-- Notes moved to trash are stored in {root}/.pkm-trash/ and recorded in
-- manifest.json. Backlinks in other notes are NOT stripped on trash —
-- they are preserved so restoration is fully reversible with no extra
-- reconstruction work. Backlinks are stripped only on permanent deletion
-- (M.empty() or M.purge_old()).
--
-- Manifest entry shape:
--   { filename, original_path, title, deleted_at, deleted_timestamp }
--   filename         — name of the file in .pkm-trash/ (may differ if collision)
--   original_path    — absolute path before deletion; used for restore and numbering
--   title            — frontmatter title at deletion time; used in picker display
--   deleted_at       — ISO 8601 UTC string; display only
--   deleted_timestamp — Unix timestamp (os.time()); used for autoclear comparison
--
-- Public API:
--   setup(config)        → store config; schedule autoclear if max_age_days > 0
--   trash_note(filepath) → move note to trash; true on success
--   restore_note(entry)  → move note back to original_path; true on success
--   list()               → array of manifest entries
--   empty()              → permanently delete all trash and strip backlinks
--   purge_old()          → permanently delete entries older than max_age_days
--   trash_dir()          → absolute path to trash folder
-- =============================================================================

local M = {}

local utils = require('pkm.utils')
local _config = nil

-- =============================================================================
-- SECTION: Internal helpers
-- =============================================================================

local function get_trash_dir()
  return utils.join(_config.root_path, '.pkm-trash')
end

local function manifest_path()
  return utils.join(get_trash_dir(), 'manifest.json')
end

local function ensure_trash_dir()
  local dir = get_trash_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
end

local function load_manifest()
  local path = manifest_path()
  if vim.fn.filereadable(path) == 0 then return {} end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or #lines == 0 then return {} end
  local raw = table.concat(lines, '\n')
  if raw:match('^%s*$') then return {} end
  local ok2, data = pcall(vim.json.decode, raw)
  if not ok2 or type(data) ~= 'table' then return {} end
  return data
end

local function save_manifest(data)
  ensure_trash_dir()
  local ok, err = pcall(vim.fn.writefile,
    { vim.json.encode(data) }, manifest_path())
  if not ok then
    vim.notify('[pkm] trash: failed to write manifest — ' .. tostring(err),
      vim.log.levels.ERROR)
    return false
  end
  return true
end

-- =============================================================================
-- SECTION: Public API
-- =============================================================================

--- Store config reference and schedule autoclear.
--- Called from pkm.init.setup().
---@param cfg table  Resolved PKM config
---@return nil
function M.setup(cfg)
  _config = cfg
  local max_days = cfg.trash and cfg.trash.max_age_days or 0
  if cfg.trash and cfg.trash.enabled and max_days > 0 then
    -- Defer 5 s so the index and citations module are ready when purge runs.
    vim.defer_fn(function() M.purge_old() end, 5000)
  end
end

--- Return the absolute path to the trash folder.
---@return string
function M.trash_dir()
  return get_trash_dir()
end

--- Return all manifest entries.
---@return table[]  Array of {filename, original_path, title, deleted_at, deleted_timestamp}
function M.list()
  return load_manifest()
end

--- Move a note file to the trash folder and record it in the manifest.
--- Backlinks in other notes are NOT stripped; they are preserved so that
--- restoration requires no extra reconstruction work.
---@param filepath string  Absolute path of the note to trash
---@return boolean success
function M.trash_note(filepath)
  if vim.fn.filereadable(filepath) == 0 then
    vim.notify('[pkm] trash: file not found: ' .. filepath, vim.log.levels.ERROR)
    return false
  end

  ensure_trash_dir()

  local filename  = vim.fn.fnamemodify(filepath, ':t')
  local trash_dst = utils.join(get_trash_dir(), filename)

  -- Avoid overwriting an existing trashed file with the same name.
  if vim.fn.filereadable(trash_dst) == 1 then
    local stem = vim.fn.fnamemodify(filename, ':r')
    local ext  = vim.fn.fnamemodify(filename, ':e')
    trash_dst  = utils.join(get_trash_dir(),
      string.format('%s_%s.%s', stem, os.date('%Y%m%d%H%M%S'), ext))
  end

  -- Read title from frontmatter for the manifest display label.
  local title = vim.fn.fnamemodify(filename, ':r'):gsub('_', ' ')
  local ok_r, disk_lines = pcall(vim.fn.readfile, filepath)
  if ok_r and type(disk_lines) == 'table' and disk_lines[1] == '---' then
    local fm = require('pkm.yaml').parse_frontmatter(disk_lines)
    if fm and type(fm.title) == 'string' and fm.title ~= '' then
      title = fm.title
    end
  end

  -- Copy then delete (avoids cross-device rename issues).
  local ok_read, data = pcall(vim.fn.readfile, filepath, 'b')
  if not ok_read then
    vim.notify('[pkm] trash: could not read note', vim.log.levels.ERROR)
    return false
  end

  if not pcall(vim.fn.writefile, data, trash_dst, 'b') then
    vim.notify('[pkm] trash: could not write to trash folder', vim.log.levels.ERROR)
    return false
  end

  if vim.fn.delete(filepath) ~= 0 then
    vim.notify('[pkm] trash: could not remove original file', vim.log.levels.ERROR)
    pcall(vim.fn.delete, trash_dst)
    return false
  end

  local now = os.time()
  local manifest = load_manifest()
  manifest[#manifest + 1] = {
    filename          = vim.fn.fnamemodify(trash_dst, ':t'),
    original_path     = filepath,
    title             = title,
    deleted_at        = os.date('!%Y-%m-%dT%H:%M:%SZ', now),
    deleted_timestamp = now,
  }
  save_manifest(manifest)
  return true
end

--- Move a trashed note back to its original location.
---@param entry table  Manifest entry
---@return boolean success
function M.restore_note(entry)
  local trash_file = utils.join(get_trash_dir(), entry.filename)
  if vim.fn.filereadable(trash_file) == 0 then
    vim.notify(
      '[pkm] restore: trashed file not found: ' .. entry.filename,
      vim.log.levels.ERROR)
    return false
  end

  if vim.fn.filereadable(entry.original_path) == 1 then
    vim.notify(
      '[pkm] restore: target path already occupied: ' .. entry.original_path,
      vim.log.levels.ERROR)
    return false
  end

  local parent_dir = vim.fn.fnamemodify(entry.original_path, ':h')
  if vim.fn.isdirectory(parent_dir) == 0 then
    vim.fn.mkdir(parent_dir, 'p')
  end

  local ok_r, data = pcall(vim.fn.readfile, trash_file, 'b')
  if not ok_r then
    vim.notify('[pkm] restore: could not read trashed file', vim.log.levels.ERROR)
    return false
  end

  if not pcall(vim.fn.writefile, data, entry.original_path, 'b') then
    vim.notify('[pkm] restore: could not write to original location',
      vim.log.levels.ERROR)
    return false
  end

  vim.fn.delete(trash_file)

  -- Remove from manifest.
  local manifest = load_manifest()
  local new_manifest = {}
  for _, e in ipairs(manifest) do
    if not (e.filename == entry.filename
        and e.original_path == entry.original_path) then
      new_manifest[#new_manifest + 1] = e
    end
  end
  save_manifest(new_manifest)

  -- Re-add to index; backlinks were never stripped, so the citation graph
  -- requires no additional reconstruction.
  require('pkm.index').invalidate(entry.original_path)
  return true
end

--- Permanently delete all trashed notes and strip their backlinks.
---@return integer  Number of notes permanently deleted
function M.empty()
  local manifest = load_manifest()
  if #manifest == 0 then return 0 end

  local citations = require('pkm.citations')
  local count = 0

  for _, entry in ipairs(manifest) do
    citations.cleanup_deleted_note(entry.original_path)
    local trash_file = utils.join(get_trash_dir(), entry.filename)
    if vim.fn.filereadable(trash_file) == 1 then
      vim.fn.delete(trash_file)
    end
    count = count + 1
  end

  save_manifest({})
  return count
end

--- Permanently delete trash entries older than config.trash.max_age_days.
--- Called automatically by setup() when max_age_days > 0.
--- Uses deleted_timestamp (Unix epoch) for comparison; falls back to parsing
--- deleted_at date for legacy entries without deleted_timestamp.
---@return integer  Number of entries purged
function M.purge_old()
  local max_days = _config.trash and _config.trash.max_age_days or 0
  if max_days <= 0 then return 0 end

  local cutoff  = os.time() - (max_days * 86400)
  local manifest = load_manifest()
  if #manifest == 0 then return 0 end

  local citations = require('pkm.citations')
  local keep   = {}
  local purged = 0

  for _, entry in ipairs(manifest) do
    -- Prefer the stored Unix timestamp; parse the date string as a fallback
    -- for manifest entries written before this field was added.
    local deleted_time = entry.deleted_timestamp
    if not deleted_time and entry.deleted_at then
      local y, mo, d = entry.deleted_at:match('^(%d+)-(%d+)-(%d+)')
      if y then
        deleted_time = os.time({
          year  = tonumber(y),  month = tonumber(mo), day  = tonumber(d),
          hour  = 0, min = 0,   sec   = 0,
        })
      end
    end

    if deleted_time and deleted_time < cutoff then
      -- cleanup_deleted_note derives the note identifier from the path stem;
      -- the file need not exist at original_path for this to work.
      citations.cleanup_deleted_note(entry.original_path)
      local trash_file = utils.join(get_trash_dir(), entry.filename)
      if vim.fn.filereadable(trash_file) == 1 then
        vim.fn.delete(trash_file)
      end
      purged = purged + 1
    else
      keep[#keep + 1] = entry
    end
  end

  if purged > 0 then
    save_manifest(keep)
    vim.notify(string.format(
      '[pkm] trash: auto-purged %d note%s older than %d days',
      purged, purged == 1 and '' or 's', max_days),
      vim.log.levels.INFO)
  end
  return purged
end

return M
