-- test/test_v1850_p3.lua
-- v1.85.0 Phase 3 — the unsaved-buffer guard sees OTHER Neovim sessions
-- (dev-report from the ferramentas-concursos consumer, item P3).
--
-- `bufsync.buffer_for` only sees the session it runs in, so a headless
-- `pkm.api` write could not see the user's editor holding the note with unsaved
-- edits. Now every pkm session with a UI registers itself (pkm.instances), and
-- `api.buffer_state` + the API's body/section/tag/citation writes ask each
-- registered session over RPC.
--
-- The "editor" here is a CHILD nvim that registers explicitly (headless has no
-- UIEnter), opens one note and modifies it, and opens a second unmodified. The
-- registry is the temp dir min_init sets in $PKM_INSTANCES_DIR, which the child
-- inherits — no real editor is ever asked.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1850_p3.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local this_file = debug.getinfo(1, 'S').source:sub(2)
local repo_root = vim.fn.fnamemodify(this_file, ':p:h:h')
local nvim_exe  = vim.v.progpath
local min_init  = repo_root .. '/test/min_init.lua'

local api   = require('pkm.api')
local inst  = require('pkm.instances')
local root  = require('pkm').config.root_path
local dir   = inst.dir()

local function read(p) return table.concat(vim.fn.readfile(p), '\n') end
local function norm(p) return vim.fs.normalize(p):lower() end

-- A server address nobody else uses: a named pipe on Windows, a socket path
-- elsewhere (the cross-platform spot-check).
local function addr(name)
  if vim.fn.has('win32') == 1 then return [[\\.\pipe\pkm-test-]] .. name end
  return vim.fn.tempname() .. '-' .. name .. '.sock'
end

check("the test registry is isolated (not the real stdpath)",
  vim.env.PKM_INSTANCES_DIR ~= nil and dir == vim.env.PKM_INSTANCES_DIR
    and not norm(dir):find(norm(vim.fn.stdpath('state')), 1, true), dir)

-- =============================================================================
print("== registry, in-process ==")
-- =============================================================================
check("setup() installed the UIEnter registration",
  #vim.api.nvim_get_autocmds({ group = 'PKMInstances', event = 'UIEnter' }) == 1)
check("a headless session did not register itself",
  vim.fn.filereadable(dir .. '/' .. vim.uv.os_getpid() .. '.json') == 0)
local own = inst.register()
check("register() writes <pid>.json", own and vim.fn.filereadable(own) == 1, own)
check("registered() never lists this session", #inst.registered() == 0, vim.inspect(inst.registered()))
inst.unregister()
check("unregister() removes it", vim.fn.filereadable(own) == 0)

-- A stale entry: a process that has exited.
local gone = vim.system({ nvim_exe, '--clean', '--headless', '-c', 'qa!' }):wait(10000)
local gone_pid = vim.system({ nvim_exe, '--clean', '--headless', '-c', 'qa!' })
local stale_pid = gone_pid.pid
gone_pid:wait(10000)
vim.fn.mkdir(dir, 'p')
local stale_file = dir .. '/' .. stale_pid .. '.json'
vim.fn.writefile({ vim.json.encode({ pid = stale_pid, server = addr('stale') }) }, stale_file)
check("a dead process's entry is ignored", #inst.registered() == 0 and gone.code == 0)
check("…and pruned from the registry", vim.fn.filereadable(stale_file) == 0)

-- =============================================================================
print("\n== a second Neovim holding notes ==")
-- =============================================================================
local n1 = api.create('note', { title = 'Held Modified', by = 'claude', body = 'one' })
local n2 = api.create('note', { title = 'Held Clean', by = 'claude', body = 'two' })
local n3 = api.create('note', { title = 'Not Held', by = 'claude', body = 'three' })
check("three notes created", n1.ok and n2.ok and n3.ok)

local child_lua = vim.fn.tempname() .. '_editor.lua'
vim.fn.writefile({
  "require('pkm.instances').register()",
  "vim.cmd('edit ' .. vim.fn.fnameescape(" .. vim.inspect(n1.path) .. "))",
  "vim.api.nvim_buf_set_lines(0, -1, -1, false, { 'UNSAVED EDIT' })",
  "local b = vim.fn.bufadd(" .. vim.inspect(n2.path) .. ")",
  "vim.fn.bufload(b)",
}, child_lua)
local child = vim.system({ nvim_exe, '--headless', '-u', min_init, '-c', 'luafile ' .. child_lua,
  '--', '--root=' .. root })
local child_file = dir .. '/' .. child.pid .. '.json'
vim.wait(15000, function() return vim.fn.filereadable(child_file) == 1 end, 100)
vim.wait(500)   -- let the child finish loading its buffers after registering

local reg = inst.registered()
check("registered() lists the other session", #reg == 1 and reg[1].pid == child.pid, vim.inspect(reg))

local st = api.buffer_state({ n1.path, n2.path, n3.path })
check("buffer_state ok + complete", st.ok and st.complete == true, vim.inspect(st.instances))
check("the other session answered",
  st.instances[1] and st.instances[1].status == 'answered' and st.instances[1].pid == child.pid,
  vim.inspect(st.instances))
check("note 1: open AND modified in the other session",
  st.notes[1].open and st.notes[1].modified and st.notes[1].where[1].pid == child.pid,
  vim.inspect(st.notes[1]))
-- The reading to exclude: "open elsewhere ⇒ modified". Note 2 is open, clean.
check("note 2: open but NOT modified", st.notes[2].open == true and st.notes[2].modified == false,
  vim.inspect(st.notes[2]))
check("note 3: not open anywhere", st.notes[3].open == false, vim.inspect(st.notes[3]))
check("summary lists", #st.modified == 1 and #st.open == 2, vim.inspect({ st.open, st.modified }))
check("buffer_state is JSON-encodable", pcall(vim.json.encode, st))

local before = read(n1.path)
local r1 = api.set_body(n1.path, 'overwritten')
check("set_body refuses the note modified elsewhere",
  r1.ok == false and tostring(r1.error):find('another Neovim (pid ' .. child.pid, 1, true) ~= nil,
  vim.inspect(r1))
check("…and wrote nothing", read(n1.path) == before)
-- Each refusal must come from the cross-session guard, not some other check.
local function refused_elsewhere(res)
  return res.ok == false and tostring(res.error):find('another Neovim', 1, true) ~= nil
end
local ra = api.append_body(n1.path, 'x')
check("append_body refuses it", refused_elsewhere(ra), vim.inspect(ra))
local ri = api.insert_section(n1.path, 'Notes', 'x')
check("insert_section refuses it", refused_elsewhere(ri), vim.inspect(ri))
local rt = api.tag_note(n1.path, { add = { 'x' } })
check("tag_note refuses it", refused_elsewhere(rt), vim.inspect(rt))
local rn = api.annotate(n1.path, 'x')
check("annotate refuses it", refused_elsewhere(rn), vim.inspect(rn))
local rc = api.cite(n3.path, n1.path)
check("cite INTO it refuses (the target gets the backlink)", refused_elsewhere(rc), vim.inspect(rc))
local rs = api.cite_source(n1.path, { title = 'Some Book', bibtex = '@book{x}' })
check("cite_source FROM it refuses", refused_elsewhere(rs), vim.inspect(rs))
check("…and the citing note is untouched", not read(n3.path):find('note[', 1, true))

local r2 = api.set_body(n2.path, 'two, rewritten')
check("set_body proceeds on a note open but clean elsewhere",
  r2.ok == true and read(n2.path):find('two, rewritten', 1, true) ~= nil, vim.inspect(r2))
local r3 = api.set_body(n3.path, 'three, rewritten')
check("set_body proceeds on a note open nowhere", r3.ok == true, vim.inspect(r3))

-- An extra address (opts.servers) that nothing listens on: reported, not blocking.
local st2 = api.buffer_state({ n3.path }, { servers = { addr('nobody-' .. vim.uv.os_getpid()) } })
local nobody
for _, i in ipairs(st2.instances) do if i.pid == nil then nobody = i end end
check("an extra server nobody listens on → 'unreachable', still complete",
  nobody and nobody.status == 'unreachable' and st2.complete == true, vim.inspect(st2.instances))

-- A registered, LIVE process whose address answers nothing (pid reused).
local sleeper = vim.system({ nvim_exe, '--clean', '--headless' })
local reused_file = dir .. '/' .. sleeper.pid .. '.json'
vim.fn.writefile({ vim.json.encode({ pid = sleeper.pid, server = addr('reused-' .. sleeper.pid) }) },
  reused_file)
check("a live pid with a dead address does not block", inst.blocking({ n3.path }) == nil)
check("…and its entry is dropped", vim.fn.filereadable(reused_file) == 0)
sleeper:kill(9)

-- A registered session that cannot answer in time: fail closed.
local busy_server = addr('busy-' .. vim.uv.os_getpid())
local busy = vim.system({ nvim_exe, '--clean', '--headless', '--listen', busy_server,
  '-c', 'lua vim.uv.sleep(6000)', '-c', 'qa!' })
vim.wait(1500)
local busy_file = dir .. '/' .. busy.pid .. '.json'
vim.fn.writefile({ vim.json.encode({ pid = busy.pid, server = busy_server }) }, busy_file)
local berr = inst.blocking({ n3.path }, { timeout = 600 })
check("a session that does not answer → the write is refused (fail closed)",
  berr ~= nil and berr:find('did not answer', 1, true) ~= nil, tostring(berr))
local st3 = api.buffer_state({ n3.path }, { timeout = 600 })
check("…and buffer_state reports complete = false", st3.complete == false, vim.inspect(st3.instances))
busy:kill(9)
vim.fn.delete(busy_file)

-- The editor quits: VimLeavePre removes its entry.
vim.system({ nvim_exe, '--clean', '--headless', '--server', reg[1].server,
  '--remote-expr', 'execute("qa!")' }):wait(5000)
child:wait(10000)
check("the other session's entry is gone after it quits",
  vim.fn.filereadable(child_file) == 0 and #inst.registered() == 0, vim.inspect(inst.registered()))
local r4 = api.set_body(n1.path, 'one, rewritten')
check("…and the note is writable again", r4.ok == true, vim.inspect(r4))

-- =============================================================================
print("\n== registration rides UIEnter (a real UI attaching) ==")
-- =============================================================================
-- An embedded nvim has no UI until one attaches over RPC — the same moment a
-- terminal UI attaches to the user's editor.
local ech  = vim.fn.jobstart({ nvim_exe, '--embed', '-u', min_init, '--', '--root=' .. root }, { rpc = true })
local epid = vim.fn.jobpid(ech)
local efile = dir .. '/' .. epid .. '.json'
vim.wait(1500)
check("no UI attached yet → not registered", vim.fn.filereadable(efile) == 0)
vim.rpcrequest(ech, 'nvim_ui_attach', 80, 24, { ext_linegrid = true })
check("a UI attaches → registered",
  vim.wait(5000, function() return vim.fn.filereadable(efile) == 1 end, 50))
pcall(vim.rpcrequest, ech, 'nvim_command', 'qa!')
check("it quits → unregistered",
  vim.wait(5000, function() return vim.fn.filereadable(efile) == 0 end, 50))

print(string.format("\n%s — %d failure(s)", failures == 0 and "PASS" or "FAIL", failures))
if failures > 0 then vim.cmd('cquit 1') end
