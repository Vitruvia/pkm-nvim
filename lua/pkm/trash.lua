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
--   original_path    — where the note came from, stored **relative to the root**
--                      with `/` separators. Read it through resolve_original(),
--                      never raw: entries written by older versions hold an
--                      absolute path, which may name another vault entirely if
--                      the tree was copied. Used for restore and numbering
--   title            — frontmatter title at deletion time; used in picker display
--   deleted_at       — ISO 8601 UTC string; display only
--   deleted_timestamp — Unix timestamp (os.time()); used for autoclear comparison
--
-- Public API:
--   setup(config)         → store config; schedule autoclear if max_age_days > 0
--   trash_note(filepath)  → move note to trash; true on success
--   restore_note(entry)   → move note back to its place in this root; true on success
--   resolve_original(e)   → absolute path under the current root for entry e
--   list()                → array of manifest entries
--   empty()               → permanently delete all trash and strip backlinks
--   purge_old()           → permanently delete entries older than max_age_days
--   trash_dir()           → absolute path to trash folder
--   open_restore_panel()  → open the browse/search/restore panel (v1.6.0 Ph2)
-- =============================================================================

local M = {}

local utils = require('pkm.utils')
local panel = require('pkm.panel')
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

-- =============================================================================
-- SECTION: Recorded location
-- =============================================================================
--
-- A manifest entry records where its note came from. That used to be an
-- absolute path, which quietly tied the trash to one directory: copy a vault
-- and its manifest still points at the original, so restoring from the copy
-- writes into the vault it was copied from. `NotesTeste` was in exactly that
-- state — entries reading `P:\Notes\03-Consolidated\…` with the files present
-- in its own `.pkm-trash/`.
--
-- The location is therefore stored **relative to the root**, with `/`
-- separators so a manifest is portable between platforms, and read back
-- through resolve_original(), which re-roots whatever form it finds. Copy,
-- rename and (later) vault switching all become safe at once, and no existing
-- manifest needs rewriting.

--- The folders a note can live under, for recognising a legacy absolute path
--- that came from a different root.
---@return string[]
local function note_folders()
  local f = _config.folders or {}
  return { f.consolidated, f.journal, f.scratchpad, f.templates }
end

--- Path separators normalised to `/`, for comparison and for storage.
---@param p string
---@return string
local function slashed(p)
  return (p:gsub('\\', '/'))
end

--- Compare-form of a path: case-folded where the filesystem folds case.
---@param p string
---@return string
local function comparable(p)
  if utils.is_windows or utils.is_wsl then return p:lower() end
  return p
end

--- The form a location is stored in: relative to the root, `/`-separated.
--- A path that is not under the root is stored unchanged — resolve_original()
--- is what re-roots it, so nothing is lost by recording what was seen.
---@param abs string  Absolute path of the note
---@return string
local function to_relative(abs)
  local p    = slashed(abs)
  local root = slashed(_config.root_path):gsub('/$', '')
  if comparable(p):sub(1, #root + 1) == comparable(root) .. '/' then
    return p:sub(#root + 2)
  end
  return p
end

--- Absolute path, under the **current** root, for a manifest entry's recorded
--- location — whichever form it was written in.
---
--- Resolution order, first match wins:
---   1. relative (the current form)      → joined onto the current root;
---   2. absolute and already under it    → taken as it stands;
---   3. absolute from elsewhere          → re-rooted from the first recognised
---      note folder onwards, which is what makes a copied or moved vault
---      restore into itself instead of into the vault it came from;
---   4. nothing recognisable             → the consolidated folder, keeping the
---      filename. A note stored at the root of another vault lands one level
---      deeper here; that is the documented cost of never writing outside the
---      current root.
---@param entry table  Manifest entry
---@return string|nil  Absolute path, or nil when the entry records nothing
function M.resolve_original(entry)
  local stored = entry and entry.original_path or ''
  if stored == '' then return nil end

  local p    = slashed(stored)
  local root = slashed(_config.root_path):gsub('/$', '')

  local is_absolute = p:match('^%a:/') ~= nil or p:sub(1, 1) == '/'
  if not is_absolute then
    return utils.normalize(root .. '/' .. p)
  end

  if comparable(p):sub(1, #root + 1) == comparable(root) .. '/' then
    return utils.normalize(p)
  end

  local known = {}
  for _, name in ipairs(note_folders()) do
    if type(name) == 'string' and name ~= '' then known[comparable(name)] = true end
  end

  local segs = vim.split(p, '/', { plain = true })
  for i = 1, #segs do
    if known[comparable(segs[i] or '')] then
      return utils.normalize(root .. '/' .. table.concat(segs, '/', i))
    end
  end

  local consolidated = (_config.folders or {}).consolidated or ''
  return utils.normalize(root .. '/' .. consolidated .. '/' .. (segs[#segs] or ''))
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
    original_path     = to_relative(filepath),
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

  -- Resolved, never the raw field: the entry may have been written by an older
  -- version, or copied in with the vault, and its absolute path may name a
  -- directory outside this root. Restoring must land inside the current vault.
  local target = M.resolve_original(entry)
  if not target then
    vim.notify('[pkm] restore: entry records no original location',
      vim.log.levels.ERROR)
    return false
  end

  if vim.fn.filereadable(target) == 1 then
    vim.notify(
      '[pkm] restore: target path already occupied: ' .. target,
      vim.log.levels.ERROR)
    return false
  end

  local parent_dir = vim.fn.fnamemodify(target, ':h')
  if vim.fn.isdirectory(parent_dir) == 0 then
    vim.fn.mkdir(parent_dir, 'p')
  end

  local ok_r, data = pcall(vim.fn.readfile, trash_file, 'b')
  if not ok_r then
    vim.notify('[pkm] restore: could not read trashed file', vim.log.levels.ERROR)
    return false
  end

  if not pcall(vim.fn.writefile, data, target, 'b') then
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
  require('pkm.index').invalidate(target)
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
    citations.cleanup_deleted_note(M.resolve_original(entry))
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
      -- NOTE: the comment that stood here claimed the file need not exist at
      -- this path. It must: cleanup_deleted_note() opens it with readfile(),
      -- which throws E484 on a trashed note — see Known Bugs. Left as it is,
      -- resolved rather than raw, because the fix is a decision about where
      -- the backlink scan should read from, not a correction to this call.
      citations.cleanup_deleted_note(M.resolve_original(entry))
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

-- =============================================================================
-- SECTION: Restore panel
-- =============================================================================

local _restore_panel = panel.create({
  name          = 'trashpanel',
  split_cmd     = 'noautocmd botright split',
  focus_on_open = true,
  resize = function(state, lines)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_height(state.win, math.min(#lines + 1, 12))
    end
  end,
  build_lines = function(state)
    local entries = M.list()

    if state.filter and state.filter ~= '' then
      local needle = state.filter:lower()
      local filtered = {}
      for _, e in ipairs(entries) do
        if (e.title or ''):lower():find(needle, 1, true)
        or (e.original_path or ''):lower():find(needle, 1, true) then
          filtered[#filtered + 1] = e
        end
      end
      entries = filtered
    end

    table.sort(entries, function(a, b)
      return (a.deleted_timestamp or 0) > (b.deleted_timestamp or 0)
    end)

    local filter_label = (state.filter and state.filter ~= '')
      and ('  [filter: ' .. state.filter .. ']') or ''
    local lines = {
      string.format('  Trash  (%d)%s  <CR> restore  / search  q close',
        #entries, filter_label),
    }
    local map = {}
    for _, e in ipairs(entries) do
      local date     = e.deleted_at and e.deleted_at:sub(1, 10) or '?'
      local rel_path = vim.fn.fnamemodify(e.original_path or '', ':~')
      lines[#lines + 1] = string.format('  [%s] %s  (%s)',
        date, e.title or '?', rel_path)
      map[#lines] = e
    end
    if #entries == 0 then
      lines[#lines + 1] = (state.filter and state.filter ~= '')
        and '  (no trashed notes match)' or '  (trash is empty)'
    end
    return lines, map
  end,
  -- Deliberately no delete key of any kind — emptying stays exclusive to
  -- :PKMEmptyTrash's typed "yes"/"no" confirmation. Do not add one here.
  keymaps = {
    ['<CR>'] = function(state, helpers)
      local entry = state.map[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not entry then return end
      if M.restore_note(entry) then
        vim.notify(string.format("[pkm] restored '%s'", entry.title),
          vim.log.levels.INFO)
        local ok, views = pcall(require, 'pkm.views')
        if ok then views.refresh_sidebar_if_open() end
        helpers.refresh()
      end
    end,

    ['/'] = function(state, helpers)
      vim.fn.inputsave()
      local query = vim.fn.input('Filter trash: ', state.filter or '')
      vim.fn.inputrestore()
      state.filter = (query and query ~= '') and query or nil
      helpers.refresh()
    end,
  },
})

--- Open the trash browse/search/restore panel. No-op with a notification
--- if trash is currently empty (matches the pre-panel :PKMRestoreNote
--- behaviour — avoids opening a panel with nothing to show).
---@return nil
function M.open_restore_panel()
  if #M.list() == 0 then
    vim.notify('[pkm] trash is empty', vim.log.levels.INFO)
    return
  end
  _restore_panel.open({ filter = '' })
end

-- Exposed for test/test_v160_p2.lua only; not part of the module's public API.
M._restore_panel = _restore_panel

return M
