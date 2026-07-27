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
--- `config.vaults_path` names it outright. Absent that it is the root's parent,
--- which is the shape the vaults actually have on disk — a root of
--- `Note-Vault/00 - NotesTeste` puts the registry at `Note-Vault/vaults.json`
--- with nothing configured. The derivation is deliberately *not* done in
--- `pkm.config`: for a root that is nobody's sibling (`~/Notes`) the answer
--- would be `~`, and storing that in the config would state as fact something
--- that is only a guess. Here it is a guess that resolves to a file which does
--- not exist, and an absent registry is a supported state.
---@return string|nil
function M.vaults_root()
  local cfg = get_config()

  if type(cfg.vaults_path) == 'string' and cfg.vaults_path ~= '' then
    return utils.normalize(vim.fn.expand(cfg.vaults_path))
  end

  local root = cfg.root_path
  if type(root) ~= 'string' or root == '' then return nil end
  return utils.normalize(vim.fn.fnamemodify(root, ':h'))
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

return M
