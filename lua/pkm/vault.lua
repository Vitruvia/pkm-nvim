-- =============================================================================
-- pkm.vault — The vault registry: which vaults exist, and which one holds a path
-- =============================================================================
-- Dependencies : pkm.utils, pkm (config, read at call time)
-- Consumed by  : pkm.commands (lifecycle, v1.11.0 Ph2)
--                pkm.init     (startup selection and switching, Ph3)
--
-- A vault is a folder. Which vault a note belongs to is therefore a fact about
-- its path, and nothing is written into the note to record it — moving a note
-- between folders moves it between vaults, which is the right behaviour for
-- something that *is* a folder, and it means the existing notes need no
-- migration at all.
--
-- The registry is `vaults.json`, one level above the vaults themselves:
--
--   Note-Vault/
--     vaults.json
--     00 - NotesTeste/
--     01 - Vitruvia/
--
-- It maps a number to a name; **the folder is derived** from the pair, never
-- stored. Renaming changes the name and the folder, renumbering changes the
-- number and the folder, and neither touches a note. That is the whole reason
-- the registry exists: without it the active vault is a hardcoded path, and
-- every rename is a search-and-replace across configuration.
--
-- The registry is optional. A `root_path` on its own keeps working exactly as
-- it always has: `list()` is empty, `of()` answers nil, and nothing errors.
-- Every test file and `min_init` depends on that, so it is load-bearing.
--
-- Public API:
--   vaults_root()          → string|nil   directory the vaults are siblings in
--   registry_path()        → string|nil   that directory's vaults.json
--   list()                 → entry[]      registered vaults, by number
--   get(name)              → entry|nil    case-insensitive lookup
--   by_number(n)           → entry|nil
--   of(path)               → entry|nil    which vault holds this path
--   active()               → entry|nil    the vault the current root is in
--   folder_of(entry)       → string       "NN - Name"
--   parse_folder(folder)   → number, name (nil when it is not a vault folder)
--   path_of(entry)         → string|nil   absolute path of a vault
--   history()              → table[]      record only; never resolves a name
--   validate_name(name)    → boolean, err?
--   validate_number(n)     → boolean, err?
--   validate(data)         → boolean, err?
--   save(data)             → boolean, err?
--   invalidate()           → drop the cached copy
--
-- Lifecycle — each returns (ok, err) and leaves folder and registry agreeing:
--   unregistered_dir()     → string|nil   where a vault goes to stop being one
--   next_number()          → integer      lowest number nobody holds
--   scaffold(path)         → the folder skeleton, named from config.folders
--   create(name, opts?)    → folder + skeleton + registry entry
--   rename(from, to)       → keeps the number, moves the folder
--   renumber(name, n)      → keeps the name, moves the folder
--   unregister(name)       → moves the folder to Unregistered/, deletes nothing
--   adopt(folder, opts?)   → the way back; takes the contents as they stand
--
-- Selection:
--   default()                 → entry|nil  the vault that opens by default,
--                               stored in the registry by number so a rename
--                               cannot invalidate it and a renumber rewrites it
--   set_default(name)         → boolean, err?
--   indicator()               → string  "01 Vitruvia", or "" — never nil
--   select(name, opts?)       → switch the active vault, invalidating what the
--                               old root produced; refuses on unsaved work
--   apply_startup_selection() → $PKM_VAULT, else config.vault, else default()
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- The registry as last read, with the stat it was read at. `of()` may be
-- called once per buffer, so re-reading the file every time is avoidable work;
-- re-reading it only when the file changed keeps a hand-edited vaults.json
-- honest without an autocmd.
local _cache = {}

--- Path separators normalised to `/`, for comparison.
--- (Same helper as pkm.trash's; three lines, and extracting it would mean a
--- second pass over trash.lua in a phase that has no other reason to touch it.)
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

local function get_config()
  local ok, pkm = pcall(require, 'pkm')
  return (ok and pkm.config) or {}
end

-- =============================================================================
-- SECTION: Where the registry lives
-- =============================================================================

--- The directory the vaults sit in as siblings, and where `vaults.json` lives.
---
--- `config.vaults_path` names it, and nothing else does. It is the single
--- absolute path in the configuration, and it names the *container* rather than
--- any vault: renaming, renumbering, unregistering and adopting all leave it
--- untouched, which is the point — no vault root is ever written down.
---
--- It is deliberately **not** derived from `root_path`'s parent. That was the
--- first shape and it was wrong: a root pointing anywhere at all — a stale one,
--- a temporary one, a plain `~/Notes` — silently designates its parent as the
--- place this module lists folders from and writes the registry into. A path
--- the user chose for one purpose must not become a write location for another.
--- Unset means no registry, which is a supported state, not a fallback.
---@return string|nil
function M.vaults_root()
  local cfg = get_config()

  if type(cfg.vaults_path) ~= 'string' or cfg.vaults_path == '' then return nil end

  -- A trailing separator is the natural way to write a directory, and it makes
  -- every path built from here `dir//child`. Windows opens such a path happily,
  -- so nothing errors — but `of()` compares it against a note path that has one
  -- separator, the prefix does not match, and the vault silently stops being
  -- recognised: no indicator, no active vault, and `:PKMVault` unable to say
  -- where you are. Stripped here rather than at every use.
  local dir = utils.normalize(vim.fn.expand(cfg.vaults_path))
  dir = (dir:gsub('[/\\]+$', ''))
  if dir == '' then return utils.sep end   -- the filesystem root, spelled "/"

  return dir
end

--- The registry file itself.
---@return string|nil
function M.registry_path()
  local dir = M.vaults_root()
  if not dir then return nil end
  return utils.join(dir, 'vaults.json')
end

-- =============================================================================
-- SECTION: The folder is derived, never stored
-- =============================================================================

--- The folder name a registry entry describes.
---@param entry table  { number, name }
---@return string
function M.folder_of(entry)
  return string.format('%02d - %s', entry.number, entry.name)
end

--- Read a folder name back into the pair that would produce it.
--- Returns nil for anything that is not a vault folder — `Unregistered`,
--- `templates`, a bare name with no number.
---@param folder string
---@return integer|nil number
---@return string|nil name
function M.parse_folder(folder)
  if type(folder) ~= 'string' then return nil end
  local num, name = folder:match('^(%d+) %- (.+)$')
  if not num then return nil end
  return tonumber(num), name
end

--- Absolute path of a registered vault.
---@param entry table|nil
---@return string|nil
function M.path_of(entry)
  local dir = M.vaults_root()
  if not dir or type(entry) ~= 'table' then return nil end
  if type(entry.number) ~= 'number' or type(entry.name) ~= 'string' then return nil end
  return utils.join(dir, M.folder_of(entry))
end

-- =============================================================================
-- SECTION: Validation
-- =============================================================================

-- Characters a Windows filename cannot hold. `:` earns its place twice: it is
-- illegal in a path *and* it is the separator in a cross-vault reference,
-- `[Vitruvia::note{0042}]` (doc/CONVENTIONS.md), so a name containing one
-- would make that syntax ambiguous on every platform.
local ILLEGAL = '[<>:"/\\|?*]'

--- Is this usable as a vault name?
---@param name any
---@return boolean ok
---@return string|nil err
function M.validate_name(name)
  if type(name) ~= 'string' or name == '' then
    return false, 'a vault name cannot be empty'
  end
  if name:match('^%s') or name:match('%s$') then
    return false, string.format('%q begins or ends with whitespace', name)
  end
  if name:find(ILLEGAL) then
    return false, string.format('%q contains one of  < > : " / \\ | ? *', name)
  end
  if name == '.' or name == '..' then
    return false, string.format('%q is not a name', name)
  end
  if name == 'Unregistered' then
    return false, '"Unregistered" is where unregistered vaults are kept'
  end

  -- The derivation has to round-trip: whatever `folder_of` writes, the folder
  -- scan in `:PKMVaultAdopt` has to read back as the same vault. This fires the
  -- moment someone changes the format string to something `parse_folder` no
  -- longer inverts, which is the failure that would otherwise surface as a
  -- vault quietly renaming itself.
  local n, back = M.parse_folder(M.folder_of({ number = 0, name = name }))
  if n ~= 0 or back ~= name then
    return false, string.format('%q does not survive the "NN - Name" form', name)
  end

  return true
end

--- Is this usable as a vault number?
---@param n any
---@return boolean ok
---@return string|nil err
function M.validate_number(n)
  if type(n) ~= 'number' or n ~= math.floor(n) or n < 0 then
    return false, 'a vault number must be a non-negative integer'
  end
  return true
end

--- Validate a whole registry: shape, every entry, and uniqueness of both keys.
---
--- Uniqueness is checked case-insensitively regardless of platform. Two vaults
--- named `Notes` and `notes` are two folders on Linux and one on Windows, and a
--- registry that is valid on one machine and self-contradictory on another is
--- worse than one that simply refuses the second name.
---@param data any
---@return boolean ok
---@return string|nil err
function M.validate(data)
  if type(data) ~= 'table' then return false, 'the registry is not a table' end
  if type(data.vaults) ~= 'table' then return false, 'the registry has no vaults list' end

  local by_number, by_name = {}, {}

  for i, v in ipairs(data.vaults) do
    if type(v) ~= 'table' then
      return false, string.format('entry %d is not a table', i)
    end

    local ok_num, err_num = M.validate_number(v.number)
    if not ok_num then return false, string.format('entry %d: %s', i, err_num) end

    local ok_name, err_name = M.validate_name(v.name)
    if not ok_name then return false, string.format('entry %d: %s', i, err_name) end

    if by_number[v.number] then
      return false, string.format('number %d is already held by %q',
        v.number, by_number[v.number])
    end
    by_number[v.number] = v.name

    local key = v.name:lower()
    if by_name[key] then
      return false, string.format('the name %q is already held by vault %d',
        v.name, by_name[key])
    end
    by_name[key] = v.number
  end

  -- The default is stored as a **number**, not a name, and the registry is what
  -- keeps it true: rename leaves a number alone, and renumber rewrites it in
  -- the same write that moves the folder. A name here would be a second place
  -- holding a name, and renaming would have to chase it.
  if data.default ~= nil then
    if not by_number[data.default] then
      return false, string.format('the default names vault %s, which is not registered',
        tostring(data.default))
    end
  end

  return true
end

-- =============================================================================
-- SECTION: Reading
-- =============================================================================

local function empty_registry()
  return { version = 1, vaults = {}, history = {} }
end

--- Read the registry, reusing the cached copy while the file is unchanged.
---@return table
local function load()
  local path = M.registry_path()
  if not path then return empty_registry() end

  local uv   = vim.uv or vim.loop
  local stat = uv.fs_stat(path)

  if not stat then
    -- No registry is a supported state, not an error: this is every test file
    -- and every user who has only ever set root_path.
    _cache = { path = path, data = empty_registry(), missing = true }
    return _cache.data
  end

  local mt = stat.mtime or {}
  if _cache.data and not _cache.missing
     and _cache.path == path
     and _cache.size == stat.size
     and _cache.sec == mt.sec and _cache.nsec == mt.nsec then
    return _cache.data
  end

  local data  = empty_registry()
  local lines = utils.read_lines(path)
  local raw   = lines and table.concat(lines, '\n') or ''

  if not raw:match('^%s*$') then
    local ok, decoded = pcall(vim.json.decode, raw)
    if ok and type(decoded) == 'table' and type(decoded.vaults) == 'table' then
      data = decoded
      data.history = type(data.history) == 'table' and data.history or {}
    else
      -- Warn once per version of the file, not once per call: the cache below
      -- is what stops this becoming a notification on every keystroke.
      utils.notify('vaults.json is malformed — treating the registry as empty',
        vim.log.levels.ERROR)
    end
  end

  _cache = { path = path, data = data, size = stat.size, sec = mt.sec, nsec = mt.nsec }
  return data
end

--- Drop the cached registry, forcing the next read to go to disk.
function M.invalidate()
  _cache = {}
end

--- Every registered vault, ordered by number.
--- The entries are copies: mutating one cannot corrupt the cached registry.
---@return table[] entries  { number, name }
function M.list()
  local out = {}

  for _, v in ipairs(load().vaults or {}) do
    if type(v) == 'table' and type(v.number) == 'number' and type(v.name) == 'string' then
      out[#out + 1] = { number = v.number, name = v.name }
    end
  end

  table.sort(out, function(a, b) return a.number < b.number end)
  return out
end

--- Look a vault up by name, case-insensitively.
---@param name string
---@return table|nil entry
function M.get(name)
  if type(name) ~= 'string' then return nil end
  local want = name:lower()

  for _, v in ipairs(M.list()) do
    if v.name:lower() == want then return v end
  end
  return nil
end

--- Look a vault up by number.
---@param n integer
---@return table|nil entry
function M.by_number(n)
  for _, v in ipairs(M.list()) do
    if v.number == n then return v end
  end
  return nil
end

--- The vault to open when nothing says otherwise.
---
--- It lives in the registry rather than in the user's config, and that is the
--- whole point: the registry is what performs a rename, so it is the only place
--- that can keep a reference true across one. A name written in `init.lua`
--- cannot be corrected by a rename, because a rename never reads `init.lua`.
--- Stored as a number for the same reason — rename does not touch it, and
--- renumber rewrites it in the same write that moves the folder.
---@return table|nil entry
function M.default()
  local n = load().default
  if type(n) ~= 'number' then return nil end
  return M.by_number(n)
end

--- The rename/renumber record. **Never consulted to resolve a name** — a name
--- means whatever it means today, and only today. This exists so a later
--- `:PKMCheck` can say "that reference names a vault renamed on such a date"
--- instead of falling silent. Because it is not a namespace, it cannot collide
--- with one.
---@return table[]
function M.history()
  return vim.deepcopy(load().history or {})
end

--- Which vault holds this path?
---
--- Longest prefix wins, so a vault that sits inside another's folder — which
--- the commands never create, but a user can — is answered with the innermost.
---
--- The comparison is plain text, never a Lua pattern. Every folder name here
--- contains ` - `, and in a pattern `-` is a lazy quantifier on the space
--- before it, so `00 - Alpha` reads as "00, then any spaces, then ` Alpha`".
--- Used as a pattern it matches the folder `00 Alpha` — a different directory
--- no vault claims — and does **not** match `00 - Alpha` itself. It gets both
--- answers wrong, in both directions.
---@param path string
---@return table|nil entry
function M.of(path)
  if type(path) ~= 'string' or path == '' then return nil end

  local p = comparable(slashed(path))
  local best, best_len = nil, -1

  for _, v in ipairs(M.list()) do
    local vp = comparable(slashed(M.path_of(v) or ''))
    vp = (vp:gsub('/+$', ''))
    if vp ~= '' and #vp > best_len
    and (p == vp or p:sub(1, #vp + 1) == vp .. '/') then
      best, best_len = v, #vp
    end
  end

  return best
end

--- The vault the active root is in, or nil when the root is outside every
--- registered vault (which includes having no registry at all).
---@return table|nil entry
function M.active()
  return M.of(get_config().root_path or '')
end

-- =============================================================================
-- SECTION: Writing
-- =============================================================================

--- Render a table as a one-line JSON object, `first_keys` in that order and
--- anything else after them, alphabetically. Keys the caller did not anticipate
--- are carried through rather than dropped: a registry someone hand-edited must
--- survive being written back.
---@param t table
---@param first_keys string[]
---@return string
local function encode_object(t, first_keys)
  local parts, seen = {}, {}

  local function put(k)
    parts[#parts + 1] = vim.json.encode(k) .. ': ' .. vim.json.encode(t[k])
  end

  for _, k in ipairs(first_keys) do
    if t[k] ~= nil then
      seen[k] = true
      put(k)
    end
  end

  local rest = {}
  for k in pairs(t) do
    if not seen[k] and type(k) == 'string' then rest[#rest + 1] = k end
  end
  table.sort(rest)
  for _, k in ipairs(rest) do put(k) end

  return '{ ' .. table.concat(parts, ', ') .. ' }'
end

--- Render the registry as lines: one vault per line, one history entry per
--- line, in the order a human would want to read them.
---@param data table
---@return string[]
local function encode_registry(data)
  local lines = { '{', '  "version": ' .. vim.json.encode(data.version or 1) .. ',' }

  if data.default ~= nil then
    lines[#lines + 1] = '  "default": ' .. vim.json.encode(data.default) .. ','
  end

  local vaults = {}
  for _, v in ipairs(data.vaults or {}) do vaults[#vaults + 1] = v end
  table.sort(vaults, function(a, b) return a.number < b.number end)

  lines[#lines + 1] = '  "vaults": ['
  for i, v in ipairs(vaults) do
    lines[#lines + 1] = '    ' .. encode_object(v, { 'number', 'name' })
      .. (i < #vaults and ',' or '')
  end
  lines[#lines + 1] = '  ],'

  local history = data.history or {}
  lines[#lines + 1] = '  "history": ['
  for i, h in ipairs(history) do
    lines[#lines + 1] = '    ' .. encode_object(h, { 'at', 'event', 'number', 'name', 'from', 'to' })
      .. (i < #history and ',' or '')
  end
  lines[#lines + 1] = '  ]'

  lines[#lines + 1] = '}'
  return lines
end

--- Write the registry.
---
--- `Note-Vault/` is not a git repository — each vault is — so this file is the
--- one piece of state in the system that nothing else can reconstruct. It is
--- therefore written to a temporary file and renamed over the original, so an
--- interrupted write leaves the previous registry untouched, and the copy it
--- replaces is kept as `vaults.json.bak` in case a *completed* write was the
--- wrong one.
---
--- Validation happens before anything is written: a registry that would refuse
--- to load is never the file on disk.
---@param data table
---@return boolean ok
---@return string|nil err
function M.save(data)
  local ok, err = M.validate(data)
  if not ok then
    utils.notify('vaults.json not written — ' .. err, vim.log.levels.ERROR)
    return false, err
  end

  local path = M.registry_path()
  if not path then
    err = 'no vaults directory is known — set vaults_path, or a root_path inside one'
    utils.notify('vaults.json not written — ' .. err, vim.log.levels.ERROR)
    return false, err
  end

  if not utils.ensure_dir(vim.fn.fnamemodify(path, ':h')) then
    err = 'cannot create ' .. vim.fn.fnamemodify(path, ':h')
    utils.notify('vaults.json not written — ' .. err, vim.log.levels.ERROR)
    return false, err
  end

  local uv  = vim.uv or vim.loop
  local tmp = path .. '.tmp'

  local wrote, werr = pcall(vim.fn.writefile, encode_registry(data), tmp)
  if not wrote then
    err = tostring(werr)
    utils.notify('vaults.json not written — ' .. err, vim.log.levels.ERROR)
    return false, err
  end

  if uv.fs_stat(path) then
    uv.fs_copyfile(path, path .. '.bak')
  end

  local renamed, rerr = uv.fs_rename(tmp, path)
  if not renamed then
    pcall(vim.fn.delete, tmp)
    err = tostring(rerr)
    utils.notify('vaults.json not written — ' .. err, vim.log.levels.ERROR)
    return false, err
  end

  -- Drop the cache outright rather than restat: mtime is second-granular on
  -- some filesystems, and two saves inside one second would otherwise serve
  -- the first one back.
  M.invalidate()
  return true
end

-- =============================================================================
-- SECTION: Lifecycle
-- =============================================================================
--
-- Creating, renaming, renumbering, unregistering and adopting a vault. All five
-- are the same operation seen from different sides: the folder name is derived
-- from the number and the name, so changing either *is* moving the folder, and
-- no note is touched by any of it.
--
-- Every one of them writes the folder first and the registry second, and puts
-- the folder back if the registry write fails. The registry is the record of
-- what exists; a folder that moved without the record following it is the one
-- state that cannot be read back correctly.

--- Where a vault goes when it stops being one. Notes are never left without a
--- place: unregistering moves the folder here intact, and `adopt()` is the way
--- back. There is no path through these functions that deletes a note.
---@return string|nil
function M.unregistered_dir()
  local dir = M.vaults_root()
  if not dir then return nil end
  return utils.join(dir, 'Unregistered')
end

--- The lowest number no vault holds.
---@return integer
function M.next_number()
  local used = {}
  for _, v in ipairs(M.list()) do used[v.number] = true end

  local n = 0
  while used[n] do n = n + 1 end
  return n
end

--- The registry as a table safe to mutate and hand to save().
local function registry_copy()
  local data   = vim.deepcopy(load())
  data.vaults  = data.vaults or {}
  data.history = data.history or {}
  return data
end

--- Append a history record. Never read back to resolve a name — see history().
local function push_history(data, event, fields)
  local h = { at = require('pkm.timestamp').to_iso8601(), event = event }
  for k, v in pairs(fields or {}) do h[k] = v end
  data.history[#data.history + 1] = h
end

--- The vault holding this name, ignoring one number (the vault being changed).
local function name_taken(name, except_number)
  for _, v in ipairs(M.list()) do
    if v.name:lower() == name:lower() and v.number ~= except_number then return v end
  end
  return nil
end

--- The vault holding this number, ignoring one name.
local function number_taken(n, except_name)
  for _, v in ipairs(M.list()) do
    if v.number == n
    and (not except_name or v.name:lower() ~= except_name:lower()) then return v end
  end
  return nil
end

--- Every loaded buffer whose file sits inside this directory.
---@param path string
---@return integer[]
local function buffers_under(path)
  local pref = comparable(slashed(path))
  pref = (pref:gsub('/+$', ''))

  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      local nm = vim.api.nvim_buf_get_name(b)
      if nm ~= '' and comparable(slashed(nm)):sub(1, #pref + 1) == pref .. '/' then
        out[#out + 1] = b
      end
    end
  end
  return out
end

--- Move a vault's folder, carrying its open buffers to the new path.
---
--- Refused while any buffer under it is modified. After the move that buffer
--- would still name a file in a folder that no longer exists, and `:w` would
--- recreate the folder to hold it — the vault resurrected as a ghost with one
--- note in it, registered nowhere. Saving first is the only correct order, and
--- it is the user's to do.
---@param from string
---@param to string
---@return boolean ok
---@return string|nil err
---@return string[] carried  buffer names that were re-pointed
local function move_folder(from, to)
  local uv = vim.uv or vim.loop

  local open, modified = buffers_under(from), {}
  for _, b in ipairs(open) do
    if vim.bo[b].modified then
      modified[#modified + 1] = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':t')
    end
  end
  if #modified > 0 then
    return false, 'unsaved changes in ' .. table.concat(modified, ', ')
      .. ' — save or discard them first', {}
  end

  if uv.fs_stat(to) then return false, to .. ' already exists', {} end

  local moved, merr = uv.fs_rename(from, to)
  if not moved then return false, tostring(merr), {} end

  local carried = {}
  for _, b in ipairs(open) do
    local nm  = slashed(vim.api.nvim_buf_get_name(b))
    local rel = nm:sub(#slashed(from) + 2)
    local new = utils.normalize(slashed(to) .. '/' .. rel)
    if pcall(vim.api.nvim_buf_set_name, b, new) then
      pcall(vim.api.nvim_buf_call, b, function() vim.cmd('silent! edit!') end)
      carried[#carried + 1] = vim.fn.fnamemodify(new, ':t')
    end
  end

  return true, nil, carried
end

--- If the active root was inside the folder that moved, follow it.
---
--- Mutating `root_path` **in place** is what makes this propagate: the eight
--- modules that keep config hold this same table, and both `trash.trash_dir()`
--- and the sync autocmd read the root at call time. Replacing the table instead
--- would leave every one of them on the old path.
local function carry_active_root(old_path, new_path)
  local cfg  = get_config()
  local root = slashed(cfg.root_path or '')
  local oldp = (slashed(old_path):gsub('/+$', ''))
  if root == '' then return false end

  if comparable(root) == comparable(oldp) then
    cfg.root_path = utils.normalize(new_path)
    return true
  end
  if comparable(root):sub(1, #oldp + 1) == comparable(oldp) .. '/' then
    cfg.root_path = utils.normalize(slashed(new_path) .. '/' .. root:sub(#oldp + 2))
    return true
  end
  return false
end

--- Move a vault's folder and rewrite its registry entry, or do neither.
local function apply_move(entry, target, event, fields)
  local uv       = vim.uv or vim.loop
  local old_path = M.path_of(entry)
  local new_path = M.path_of(target)

  local carried = {}
  local folder_existed = uv.fs_stat(old_path) ~= nil
  if folder_existed then
    local moved, merr, names = move_folder(old_path, new_path)
    if not moved then return false, merr end
    carried = names
  else
    utils.notify(string.format('%s had no folder — the registry entry alone was changed',
      M.folder_of(entry)), vim.log.levels.WARN)
  end

  local data = registry_copy()
  for _, v in ipairs(data.vaults) do
    if v.number == entry.number and v.name == entry.name then
      v.number, v.name = target.number, target.name
    end
  end
  -- The default follows the vault it points at. This is the write that makes
  -- storing it here worth anything: the rename fixes its own reference, which
  -- is precisely what a name in the user's config could never do.
  if data.default == entry.number then data.default = target.number end
  push_history(data, event, fields)

  local saved, serr = M.save(data)
  if not saved then
    -- The registry is unchanged, so the folder must be too.
    if folder_existed then uv.fs_rename(new_path, old_path) end
    return false, serr
  end

  if carry_active_root(old_path, new_path) then
    utils.notify(string.format('the active vault moved with it — root is now %s',
      get_config().root_path), vim.log.levels.INFO)
  end
  if #carried > 0 then
    utils.notify(string.format('%d open note%s followed the move: %s',
      #carried, #carried == 1 and '' or 's', table.concat(carried, ', ')),
      vim.log.levels.INFO)
  end

  return true
end

--- The folder skeleton a new vault starts with.
---
--- The subfolder names come from `config.folders` rather than from constants,
--- so a vault is created shaped like the ones the user already has. Nothing
--- here is created on demand elsewhere except `templates` and `.pkm-trash`;
--- the rest a user has had to make by hand until now.
---@param path string
function M.scaffold(path)
  local folders = get_config().folders or {}

  for _, key in ipairs({ 'scratchpad', 'journal', 'consolidated', 'templates' }) do
    if folders[key] then utils.ensure_dir(utils.join(path, folders[key])) end
  end

  local views = utils.join(path, 'views.json')
  if vim.fn.filereadable(views) == 0 then
    pcall(vim.fn.writefile, { '{}' }, views)
  end

  local ignore = utils.join(path, '.gitignore')
  if vim.fn.filereadable(ignore) == 0 then
    pcall(vim.fn.writefile, {
      '# Soft-deleted notes, recoverable with :PKMRestoreNote.',
      '# Transient state, not history — the notes themselves are versioned.',
      '.pkm-trash/',
    }, ignore)
  end
end

local function git_init(path)
  if vim.fn.executable('git') ~= 1 then
    utils.notify('git is not on PATH — the vault was created without a repository',
      vim.log.levels.WARN)
    return false
  end

  local out = vim.fn.systemlist({ 'git', '-C', path, 'init' })
  if vim.v.shell_error ~= 0 then
    utils.notify('git init failed — ' .. table.concat(out, ' '), vim.log.levels.WARN)
    return false
  end
  return true
end

--- Create a vault: the folder, its skeleton, and the registry entry.
---@param name string
---@param opts table|nil  { number?, git? = boolean (default true),
---                         scaffold? = boolean (default true) }
---@return boolean ok
---@return string|nil err
function M.create(name, opts)
  opts = opts or {}

  local ok, err = M.validate_name(name)
  if not ok then return false, err end

  if not M.vaults_root() then
    return false, 'no vaults directory is known — set vaults_path, or a root_path inside one'
  end

  local held = name_taken(name)
  if held then
    return false, string.format('%q is already vault %02d', name, held.number)
  end

  local number = opts.number or M.next_number()
  local ok_n, err_n = M.validate_number(number)
  if not ok_n then return false, err_n end

  local held_n = number_taken(number)
  if held_n then
    return false, string.format('number %d is already held by %q', number, held_n.name)
  end

  local entry = { number = number, name = name }
  local path  = M.path_of(entry)
  local uv    = vim.uv or vim.loop

  if uv.fs_stat(path) then
    return false, string.format('%s already exists — :PKMVaultAdopt takes a folder as it stands',
      path)
  end
  if not utils.ensure_dir(path) then return false, 'cannot create ' .. path end

  if opts.scaffold ~= false then M.scaffold(path) end

  local data = registry_copy()
  data.vaults[#data.vaults + 1] = entry
  -- The first vault to exist is the one to open, until someone says otherwise.
  -- It makes the very first run work with nothing configured but vaults_path.
  if data.default == nil then data.default = number end
  push_history(data, 'new', { number = number, name = name })

  local saved, serr = M.save(data)
  if not saved then
    -- The folder stays. It holds nothing, but removing a directory is still
    -- removing a directory, and saying where it is costs the user one command.
    return false, string.format('%s — the folder at %s was created and is not registered',
      serr, path)
  end

  if opts.git ~= false then git_init(path) end
  return true
end

--- Rename a vault. The number is kept, so the folder moves and nothing else
--- about the vault's identity changes.
---
--- There are no aliases: the old name stops meaning anything the moment this
--- returns. Keeping it as a second name is what would let vault 01 be renamed
--- to vault 02's old name and answer to it — the collision this refuses.
---@param from string
---@param to string
---@return boolean ok
---@return string|nil err
function M.rename(from, to)
  local entry = M.get(from)
  if not entry then return false, string.format('no vault is named %q', from) end

  local ok, err = M.validate_name(to)
  if not ok then return false, err end

  if entry.name == to then
    return false, string.format('%q is already its name', to)
  end

  local held = name_taken(to, entry.number)
  if held then
    return false, string.format('the name %q is already held by vault %02d', to, held.number)
  end

  return apply_move(entry, { number = entry.number, name = to },
    'rename', { number = entry.number, from = entry.name, to = to })
end

--- Renumber a vault. The name is kept.
---@param name string
---@param number integer
---@return boolean ok
---@return string|nil err
function M.renumber(name, number)
  local entry = M.get(name)
  if not entry then return false, string.format('no vault is named %q', name) end

  local ok, err = M.validate_number(number)
  if not ok then return false, err end

  if entry.number == number then
    return false, string.format('%q is already vault %02d', entry.name, number)
  end

  local held = number_taken(number, entry.name)
  if held then
    return false, string.format('number %d is already held by %q', number, held.name)
  end

  return apply_move(entry, { number = number, name = entry.name },
    'renumber', { name = entry.name, from = entry.number, to = number })
end

--- Take a vault out of the registry, moving its folder to `Unregistered/`.
---
--- The notes are not deleted and are not offered for deletion: each vault is a
--- git repository, and the file manager removes one visibly and into the
--- system's own recycle bin. What this does is exactly reversible by adopt().
---@param name string
---@return boolean ok
---@return string|nil err
function M.unregister(name)
  local entry = M.get(name)
  if not entry then return false, string.format('no vault is named %q', name) end

  local act = M.active()
  if act and act.number == entry.number and act.name == entry.name then
    return false, string.format(
      '%q is the active vault — moving it out from under the session would leave '
      .. 'every open path naming nothing; switch away first', entry.name)
  end

  local dest_dir = M.unregistered_dir()
  if not dest_dir or not utils.ensure_dir(dest_dir) then
    return false, 'cannot create ' .. tostring(dest_dir)
  end

  local uv   = vim.uv or vim.loop
  local dest = utils.join(dest_dir, entry.name)
  if uv.fs_stat(dest) then
    return false, string.format('%s already exists — a previous %q is still there',
      dest, entry.name)
  end

  local from = M.path_of(entry)
  local moved_folder = uv.fs_stat(from) ~= nil
  if moved_folder then
    local moved, merr = move_folder(from, dest)
    if not moved then return false, merr end
  end

  local data, kept = registry_copy(), {}
  for _, v in ipairs(data.vaults) do
    if not (v.number == entry.number and v.name == entry.name) then
      kept[#kept + 1] = v
    end
  end
  data.vaults = kept
  -- A default pointing at a vault that is no longer registered would fail
  -- validation on the very next write. Cleared, not carried to a neighbour:
  -- which vault becomes the default is the user's to say.
  if data.default == entry.number then data.default = nil end
  push_history(data, 'unregister', { number = entry.number, name = entry.name })

  local saved, serr = M.save(data)
  if not saved then
    if moved_folder then uv.fs_rename(dest, from) end
    return false, serr
  end

  return true
end

--- Register a folder that is not a vault, without changing what is inside it.
---
--- Looks under `Unregistered/` first, then beside the vaults. A folder already
--- shaped `NN - Name` proposes its own number and name; anything else takes the
--- next free number and its own folder name. The contents are taken exactly as
--- they stand — no skeleton is imposed on notes that already have a shape.
---@param folder string  Folder name, not a path
---@param opts table|nil { number?, name? }
---@return boolean ok
---@return string|nil err
---@return table|nil entry  the vault it became, for the caller to report
function M.adopt(folder, opts)
  opts = opts or {}

  local dir = M.vaults_root()
  if not dir then
    return false, 'no vaults directory is known — set vaults_path, or a root_path inside one'
  end

  local uv  = vim.uv or vim.loop
  local src = utils.join(M.unregistered_dir(), folder)
  if not uv.fs_stat(src) then
    src = utils.join(dir, folder)
    if not uv.fs_stat(src) then
      return false, string.format('no folder %q under Unregistered/ or beside the vaults', folder)
    end
  end

  local folder_number, folder_name = M.parse_folder(folder)
  local name   = opts.name   or folder_name   or folder
  local number = opts.number or folder_number or M.next_number()

  local ok, err = M.validate_name(name)
  if not ok then return false, err end

  local ok_n, err_n = M.validate_number(number)
  if not ok_n then return false, err_n end

  local held = name_taken(name)
  if held then
    return false, string.format('the name %q is already held by vault %02d', name, held.number)
  end

  local held_n = number_taken(number)
  if held_n then
    return false, string.format('number %d is already held by %q — adopt it under another',
      number, held_n.name)
  end

  local entry = { number = number, name = name }
  local dest  = M.path_of(entry)

  local moved_folder = comparable(slashed(src)) ~= comparable(slashed(dest))
  if moved_folder then
    if uv.fs_stat(dest) then return false, dest .. ' already exists' end
    local moved, merr = move_folder(src, dest)
    if not moved then return false, merr end
  end

  local data = registry_copy()
  data.vaults[#data.vaults + 1] = entry
  if data.default == nil then data.default = number end
  push_history(data, 'adopt', { number = number, name = name, from = folder })

  local saved, serr = M.save(data)
  if not saved then
    if moved_folder then uv.fs_rename(dest, src) end
    return false, serr
  end

  return true, nil, entry
end

-- =============================================================================
-- SECTION: Choosing the active vault
-- =============================================================================
--
-- After a switch the two vaults look identical on screen, and every destructive
-- command acts on "the vault". No amount of code fixes that; only saying which
-- one does. So the indicator is published on every path through this section,
-- including the ones that fail.

--- The active vault as a label — `"01 Vitruvia"`, or an empty string when no
--- registered vault holds the root. Never nil, so a statusline can concatenate
--- it without a guard.
---@return string
function M.indicator()
  local entry = M.active()
  if not entry then return '' end
  return string.format('%02d %s', entry.number, entry.name)
end

--- Publish the active vault where a statusline and the panels can read it.
local function publish()
  vim.g.pkm_vault = M.indicator()
end

--- Point the plugin at another vault.
---
--- Three things have to happen, and the order is what makes it safe.
---
--- First, refuse while the vault being left holds unsaved work. After the
--- switch that buffer is outside the root: `in_root` answers false, so saving
--- it stops stamping its timestamp, stops syncing citations and stops touching
--- the index. It still looks like a note and has quietly stopped being treated
--- as one.
---
--- Then move the root, in place — the eight modules that keep config hold this
--- same table.
---
--- Then discard everything derived from the old root. This is the step that
--- corrupts if it is skipped: `views.json` lives *inside* the root, so a stale
--- sidecar evaluates one vault's saved views against another's notes, and a
--- stale index lists notes that are not there.
---@param name string
---@param opts table|nil { force? = boolean — switch despite unsaved buffers }
---@return boolean ok
---@return string|nil err
---@return table|nil entry
function M.select(name, opts)
  opts = opts or {}

  local entry = M.get(name)
  if not entry then
    publish()
    return false, string.format('no vault is named %q', name)
  end

  local path = M.path_of(entry)
  if vim.fn.isdirectory(path) == 0 then
    publish()
    return false, string.format('%s is registered but its folder is not there',
      M.folder_of(entry))
  end

  local cfg = get_config()
  if comparable(slashed(cfg.root_path or '')) == comparable(slashed(path)) then
    publish()
    return true, nil, entry
  end

  if not opts.force then
    local dirty = {}
    for _, b in ipairs(buffers_under(cfg.root_path or '')) do
      if vim.bo[b].modified then
        dirty[#dirty + 1] = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':t')
      end
    end
    if #dirty > 0 then
      publish()
      return false, string.format(
        'unsaved changes in %s — after the switch those buffers sit outside the root, '
        .. 'where saving no longer updates the timestamp, the citations or the index',
        table.concat(dirty, ', '))
    end
  end

  cfg.root_path = utils.normalize(path)

  -- Everything the old root produced, dropped together.
  pcall(function() require('pkm.views').invalidate() end)
  pcall(function()
    local index = require('pkm.index')
    if index.is_built() then index.rebuild() end
  end)
  pcall(function() require('pkm.views').refresh_sidebar_if_open() end)

  publish()
  return true, nil, entry
end

--- Make a vault the one that opens when nothing says otherwise.
---
--- Recorded by number, in the registry, so a later rename cannot invalidate it
--- and a later renumber rewrites it.
---@param name string
---@return boolean ok
---@return string|nil err
function M.set_default(name)
  local entry = M.get(name)
  if not entry then return false, string.format('no vault is named %q', name) end

  local data = registry_copy()
  if data.default == entry.number then return true end

  data.default = entry.number
  push_history(data, 'default', { number = entry.number, name = entry.name })
  return M.save(data)
end

--- Say what is missing when a vaults_path is configured but no vault opens.
---
--- This is the first run, and the only useful message names the folders that
--- are already sitting there. Reporting the root instead — which at this point
--- is the plugin's own `~/Notes` placeholder — describes a path the user never
--- chose and does not mention the one command that fixes it.
---
--- A warning rather than an error: nothing is broken, the setup is simply not
--- finished, and it stops the moment a vault is registered.
function M.report_no_default()
  local dir = M.vaults_root()
  if not dir then return end

  if #M.list() > 0 then
    utils.notify(string.format(
      'no default vault — :PKMVault! <name> picks the one to open (registered: %s)',
      table.concat(vim.tbl_map(function(v) return v.name end, M.list()), ', ')),
      vim.log.levels.WARN)
    return
  end

  local found = {}
  for _, path in ipairs(vim.fn.glob(dir .. '/*', false, true)) do
    local leaf = vim.fn.fnamemodify(path, ':t')
    if vim.fn.isdirectory(path) == 1 and leaf ~= 'Unregistered' then
      found[#found + 1] = string.format('%q', leaf)
    end
  end

  if #found > 0 then
    utils.notify(string.format(
      'no vault is registered yet — :PKMVaultAdopt registers what is already in %s (%s)',
      dir, table.concat(found, ', ')), vim.log.levels.WARN)
  else
    utils.notify(string.format(
      'no vault is registered, and %s holds no folder to adopt — :PKMVaultNew <name> makes one',
      dir), vim.log.levels.WARN)
  end
end

--- Resolve a vault chosen by name into the active root, once, at startup.
---
--- `$PKM_VAULT` outranks `config.vault`: pointing the real configuration at the
--- test vault for a single session, without editing init.lua, is the reason the
--- startup form exists at all.
---
--- Nothing derived exists yet when this runs — no index, no view caches, no
--- open notes — which is why it needs none of the invalidation `select()` does.
--- That is also why it must run before the modules are handed the config.
---@return boolean applied
function M.apply_startup_selection()
  local cfg = get_config()

  -- Most specific wins: a variable set for this session, then a name written
  -- in the config, then the registry's own default. The last one is the
  -- ordinary case and the only one that survives a rename, because it is the
  -- registry — the thing that performs renames — holding the reference.
  local name = vim.env.PKM_VAULT
  if name == nil or name == '' then name = cfg.vault end

  if type(name) ~= 'string' or name == '' then
    -- No vaults_path at all is a plain root_path configuration, which is
    -- supported and says nothing. A vaults_path with no default is the first
    -- run, and it is the one moment the user needs to be told what to do.
    if not M.vaults_root() then
      publish()
      return false
    end
    local fallback = M.default()
    if not fallback then
      M.report_no_default()
      publish()
      return false
    end
    name = fallback.name
  end

  if not M.vaults_root() then
    utils.notify(string.format(
      'vault = %q needs vaults_path, the directory the vaults sit in — without it '
      .. 'there is no registry to resolve the name against', name), vim.log.levels.ERROR)
    publish()
    return false
  end

  local entry = M.get(name)
  if not entry then
    -- The first run of all: the folders exist, the registry does not yet.
    -- Saying so beats reporting a missing vault the user can see on disk.
    local hint = ''
    for _, path in ipairs(vim.fn.glob(M.vaults_root() .. '/*', false, true)) do
      local leaf = vim.fn.fnamemodify(path, ':t')
      local _, folder_name = M.parse_folder(leaf)
      if vim.fn.isdirectory(path) == 1 and folder_name
      and folder_name:lower() == name:lower() then
        hint = string.format(' — the folder is there; :PKMVaultAdopt "%s" registers it', leaf)
      end
    end
    utils.notify(string.format('no vault named %q is registered%s', name, hint),
      vim.log.levels.ERROR)
    publish()
    return false
  end

  local path = M.path_of(entry)
  if vim.fn.isdirectory(path) == 0 then
    utils.notify(string.format('%s is registered but its folder is not there — staying on %s',
      M.folder_of(entry), tostring(cfg.root_path)), vim.log.levels.ERROR)
    publish()
    return false
  end

  cfg.root_path = utils.normalize(path)
  publish()
  return true
end

return M
