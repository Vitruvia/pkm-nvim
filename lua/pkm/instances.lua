-- =============================================================================
-- pkm.instances — which OTHER Neovim sessions hold a note open
-- =============================================================================
-- Dependencies : pkm.utils, pkm.bufsync, pkm (config.root_path, recorded only)
-- Consumed by  : pkm.init (setup: registration), pkm.api (buffer_state and the
--                cross-instance write guard)
--
-- The unsaved-buffer guard (`bufsync.buffer_for`) sees only the Neovim it runs
-- in. A headless `pkm.api` call is a *different* process from the user's editor,
-- so it could not see the one case the guard exists for: the user has the note
-- open in their interactive session, with unsaved edits, while an assistant
-- writes it on disk. Their next `:w` then silently undoes the assistant's write
-- (or the assistant's write is lost to theirs).
--
-- Why not swap files: they are the classic cross-process signal, but they only
-- exist where 'swapfile' is on and in a 'directory' the reader has to guess —
-- and the author's own config sets `noswapfile`, so a swap scan is blind exactly
-- where it matters. Asking the session is the only reliable answer.
--
-- So every pkm-nvim session that has a UI REGISTERS itself: on `UIEnter` it
-- writes `<dir>/<pid>.json` = { pid, server = v:servername, root }, and removes
-- it on `VimLeavePre`. A checker reads the directory, drops entries whose
-- process is gone, and asks each live session — over its RPC server, through a
-- short-lived `nvim --server … --remote-expr` with a timeout, so a stuck editor
-- can never hang the caller — which buffers it has loaded and whether they are
-- modified. Headless sessions (scripts, assistants, tests) never fire UIEnter,
-- so they never register and are never asked.
--
-- The registry lives in `stdpath('state')/pkm/instances`, shared by every
-- session of the same Neovim install; `$PKM_INSTANCES_DIR` overrides it (the
-- test init points it at a temp dir so tests never reach a real editor).
--
-- Public API:
--   dir()                     → the registry directory
--   setup()                   → register on UIEnter (now, if a UI is attached),
--                               unregister on VimLeavePre
--   register() / unregister() → explicit forms (setup uses them; tests too)
--   registered()              → live entries { pid, server, root, file }; prunes
--                               entries whose process is gone
--   query(server, timeout)    → (bufs|nil, status) — status 'answered' |
--                               'timeout' | 'unreachable' | 'error'
--   state(paths, opts)        → per-note open/modified across this session and
--                               every registered one (pkm.api.buffer_state)
--   blocking(paths, opts)     → nil, or the reason a write must not proceed
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

local DEFAULT_TIMEOUT = 2000   -- ms one session gets to answer

-- The remote side runs plain Neovim API only: the asked session need not have
-- this version of pkm (or pkm at all) loaded.
local REMOTE_EXPR = 'luaeval("vim.json.encode(vim.tbl_map(function(b) return { '
  .. 'vim.api.nvim_buf_get_name(b), vim.bo[b].modified } end, '
  .. 'vim.tbl_filter(vim.api.nvim_buf_is_loaded, vim.api.nvim_list_bufs())))")'

-- =============================================================================
-- SECTION: Registry
-- =============================================================================

--- The registry directory: `$PKM_INSTANCES_DIR`, else
--- `stdpath('state')/pkm/instances`.
---@return string
function M.dir()
  local env = vim.env.PKM_INSTANCES_DIR
  if type(env) == 'string' and env ~= '' then return env end
  return vim.fn.stdpath('state') .. '/pkm/instances'
end

local function own_file()
  return M.dir() .. '/' .. vim.uv.os_getpid() .. '.json'
end

--- Record this session in the registry. Idempotent. Starts an RPC server first
--- if the session has none, since the entry is useless without an address.
---@return string|nil file  the entry written, or nil on failure
function M.register()
  local server = vim.v.servername
  if type(server) ~= 'string' or server == '' then
    local ok, addr = pcall(vim.fn.serverstart)
    if not ok or type(addr) ~= 'string' or addr == '' then return nil end
    server = addr
  end
  vim.fn.mkdir(M.dir(), 'p')
  local entry = {
    pid    = vim.uv.os_getpid(),
    server = server,
    root   = (require('pkm').config or {}).root_path,
  }
  local file = own_file()
  local ok = pcall(vim.fn.writefile, { vim.json.encode(entry) }, file)
  return ok and file or nil
end

--- Remove this session's entry.
function M.unregister()
  pcall(vim.fn.delete, own_file())
end

--- Register when a UI attaches, unregister on exit. A session whose UI is
--- already attached (pkm lazy-loaded after startup) registers at once.
function M.setup()
  local group = vim.api.nvim_create_augroup('PKMInstances', { clear = true })
  vim.api.nvim_create_autocmd('UIEnter', {
    group    = group,
    callback = function() M.register() end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group    = group,
    callback = function() M.unregister() end,
  })
  if #vim.api.nvim_list_uis() > 0 then M.register() end
end

--- Is a process with this pid still running?
---@param pid integer
---@return boolean
local function alive(pid)
  local ok, err = vim.uv.kill(pid, 0)
  if ok == 0 then return true end
  -- EPERM: it exists but belongs to someone else — still alive.
  return err ~= nil and tostring(err):find('EPERM', 1, true) ~= nil
end

--- The live registered sessions other than this one. An entry whose process is
--- gone (a crash skipped VimLeavePre) is deleted on the way.
---@return table[]  { pid, server, root, file }
function M.registered()
  local out, me = {}, vim.uv.os_getpid()
  local dir = M.dir()
  if vim.fn.isdirectory(dir) == 0 then return out end
  for _, name in ipairs(vim.fn.readdir(dir)) do
    if name:match('^%d+%.json$') then
      local file = dir .. '/' .. name
      local ok, entry = pcall(function()
        return vim.json.decode(table.concat(vim.fn.readfile(file), '\n'))
      end)
      if ok and type(entry) == 'table' and type(entry.pid) == 'number'
          and type(entry.server) == 'string' then
        if entry.pid ~= me then
          if alive(entry.pid) then
            out[#out + 1] = { pid = entry.pid, server = entry.server, root = entry.root, file = file }
          else
            pcall(vim.fn.delete, file)
          end
        end
      else
        pcall(vim.fn.delete, file)   -- unreadable entry: never trusted, never kept
      end
    end
  end
  table.sort(out, function(a, b) return a.pid < b.pid end)
  return out
end

-- =============================================================================
-- SECTION: Asking a session
-- =============================================================================

--- Ask the session at `server` which buffers it has loaded.
---@param server string
---@param timeout integer|nil  ms (default 2000)
---@return table|nil bufs  { { name, modified }, … }
---@return string status   'answered' | 'timeout' | 'unreachable' (nothing listens) | 'error'
---@return string|nil err
function M.query(server, timeout)
  local ok, res = pcall(function()
    return vim.system({ vim.v.progpath, '--clean', '--headless', '--server', server,
      '--remote-expr', REMOTE_EXPR }, { text = true }):wait(timeout or DEFAULT_TIMEOUT)
  end)
  if not ok then return nil, 'error', tostring(res) end
  if res.code == 124 then return nil, 'timeout', 'no answer within ' .. (timeout or DEFAULT_TIMEOUT) .. ' ms' end
  if res.code ~= 0 then
    local msg = vim.trim((res.stderr or '') .. (res.stdout or ''))
    -- E247 = nothing listens at that address (connection refused / no pipe).
    if msg:find('E247', 1, true) then return nil, 'unreachable', msg end
    return nil, 'error', msg
  end
  local dok, list = pcall(vim.json.decode, vim.trim(res.stdout or ''))
  if not dok or type(list) ~= 'table' then
    return nil, 'error', 'unreadable answer: ' .. tostring(res.stdout)
  end
  local bufs = {}
  for _, b in ipairs(list) do
    if type(b) == 'table' and type(b[1]) == 'string' then
      bufs[#bufs + 1] = { name = b[1], modified = b[2] == true }
    end
  end
  return bufs, 'answered'
end

-- =============================================================================
-- SECTION: State and the write guard
-- =============================================================================

local function key(path)
  return utils.normalize(vim.fn.fnamemodify(path, ':p')):lower()
end

--- Where are these notes open, and are they modified? Covers this session and
--- every registered one (plus `opts.servers`, extra addresses to ask).
---@param paths string[]
---@param opts table|nil  { servers?: string[], timeout?: integer, others_only?: boolean }
---@return table  { notes = { { path, open, modified, where = { { pid, modified, self? } } } },
---                 instances = { { pid?, server, status, error? } }, complete }
function M.state(paths, opts)
  opts = opts or {}
  local notes, by_key = {}, {}
  for i, p in ipairs(paths or {}) do
    notes[i] = { path = p, open = false, modified = false, where = {} }
    by_key[key(p)] = notes[i]
  end

  local function mark(n, pid, modified, is_self)
    n.open = true
    if modified then n.modified = true end
    n.where[#n.where + 1] = { pid = pid, modified = modified, self = is_self or nil }
  end

  -- This session.
  if not opts.others_only then
    local bufsync = require('pkm.bufsync')
    for _, n in ipairs(notes) do
      local bufnr = bufsync.buffer_for(n.path)
      if bufnr then mark(n, vim.uv.os_getpid(), vim.bo[bufnr].modified, true) end
    end
  end

  -- Every other session: the registry, then any extra address (deduplicated).
  local targets, seen = {}, {}
  for _, e in ipairs(M.registered()) do
    if not seen[e.server] then
      seen[e.server] = true
      targets[#targets + 1] = { pid = e.pid, server = e.server, file = e.file }
    end
  end
  for _, s in ipairs(opts.servers or {}) do
    if type(s) == 'string' and s ~= '' and s ~= vim.v.servername and not seen[s] then
      seen[s] = true
      targets[#targets + 1] = { server = s }
    end
  end

  local instances, complete = {}, true
  for _, t in ipairs(targets) do
    local bufs, status, err = M.query(t.server, opts.timeout)
    instances[#instances + 1] = { pid = t.pid, server = t.server, status = status, error = err }
    if status == 'answered' then
      for _, b in ipairs(bufs) do
        local n = b.name ~= '' and by_key[key(b.name)]
        if n then mark(n, t.pid, b.modified) end
      end
    elseif status == 'unreachable' then
      -- No server answers at that address: nothing there can hold a buffer.
      -- For a registered entry (process alive) the pid was reused or the
      -- session lost its server — drop the entry.
      if t.file then pcall(vim.fn.delete, t.file) end
    else
      complete = false
    end
  end

  return { notes = notes, instances = instances, complete = complete }
end

--- The reason a write to these notes must not proceed, or nil: one is modified
--- in ANOTHER registered session, or a registered session did not answer in
--- time (fail closed — "could not check" is not "clear"). Open-but-unmodified
--- elsewhere does not block: that session sees the file change on its own.
--- This session's own buffers are the cores' guard, not this one.
---@param paths string[]
---@param opts table|nil  { timeout?: integer }
---@return string|nil err
function M.blocking(paths, opts)
  local st = M.state(paths, { others_only = true, timeout = (opts or {}).timeout })
  for _, n in ipairs(st.notes) do
    for _, w in ipairs(n.where) do
      if w.modified then
        return string.format(
          'the note has unsaved changes in another Neovim (pid %s) — save it there first: %s',
          tostring(w.pid), n.path)
      end
    end
  end
  for _, inst in ipairs(st.instances) do
    if inst.status == 'timeout' or inst.status == 'error' then
      return string.format(
        'another Neovim (pid %s, %s) did not answer (%s) — cannot confirm the note is not being edited there',
        tostring(inst.pid), inst.server, tostring(inst.error))
    end
  end
  return nil
end

return M
