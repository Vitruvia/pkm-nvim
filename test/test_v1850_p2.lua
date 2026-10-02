-- test/test_v1850_p2.lua
-- v1.85.0 Phase 2 — the headless traps, verified (dev-report from the
-- ferramentas-concursos consumer, item P2).
--
-- Each trap the consumer reported is reproduced here before the docs describe
-- it, so the docs state behaviour that was observed, not remembered:
--   * a `[[wikilink]]` closes a `[[…]]` long string; `[==[ … ]==]` survives it;
--   * a Lua error under `-c "luafile …"` still exits 0, while `-l` exits 1 —
--     which is why the docs now recommend a task file run with `-l`;
--   * `emit` writes raw UTF-8 to stdout (no \u escapes), so the caller must
--     decode it as UTF-8;
--   * the shipped init leaves no swap file behind (`swapfile` off);
--   * `resolve('0056')` with a bare number: before, always "no note matches";
--     now it resolves when exactly one consolidated note holds the number, and
--     refuses (naming the holders) when several do.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1850_p2.lua" -c "qa!"

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
local init_path = repo_root .. '/scripts/headless_init.lua'

local function run(args)
  local res = vim.system(args, { text = true }):wait(60000)
  return { code = res.code, stdout = res.stdout or '', stderr = res.stderr or '' }
end

local function last_json(stdout)
  local last
  for line in stdout:gmatch('[^\r\n]+') do
    if line:sub(1, 1) == '{' then last = line end
  end
  if not last then return nil end
  local ok, v = pcall(vim.json.decode, last)
  return ok and v or nil
end

local function write(path, lines) vim.fn.writefile(lines, path) end

local function fresh_root()
  local r = vim.fn.tempname() .. '/Note-Vault/00 - Test'
  vim.fn.mkdir(r .. '/03-Consolidated', 'p')
  return r
end

-- =============================================================================
print("== resolve: bare numbers (in-process) ==")
-- =============================================================================
local api   = require('pkm.api')
local index = require('pkm.index')

local a = api.create('note', { title = 'Bare Alpha', by = 'claude', body = 'alpha body' })
local b = api.create('note', { title = 'Bare Beta', by = 'claude', body = 'beta body' })
check("two notes created", a.ok and b.ok, vim.inspect({ a, b }))
local num_a = string.format('%04d', a.number)

-- The reading to exclude: "a bare number resolves to SOME note" — so resolve
-- the second note's number and require the second note, not the first.
local rb = api.resolve(string.format('%04d', b.number))
check("resolve('<padded number>') finds exactly that note",
  rb.ok and rb.path and vim.fs.normalize(rb.path) == vim.fs.normalize(b.path), vim.inspect(rb))
local ru = api.resolve(tostring(a.number))
check("resolve('<unpadded number>') finds it too",
  ru.ok and vim.fs.normalize(ru.path) == vim.fs.normalize(a.path), vim.inspect(ru))
check("resolve gives the identifier to store", ru.identifier == 'note-' .. num_a, vim.inspect(ru))

local rn = api.resolve('9999')
check("an unheld number → ok=false 'no note matches'",
  rn.ok == false and tostring(rn.error):find('no note matches', 1, true) ~= nil, vim.inspect(rn))

local rd = api.read(num_a)
check("read('<number>') reads the note", rd.ok and rd.title == 'Bare Alpha', vim.inspect(rd and rd.title))

local rc = api.cite(b.path, num_a)
check("cite(src, '<number>') records the citation", rc.ok == true, vim.inspect(rc))
local rb2 = api.read(b.path)
check("…and the graph has the edge",
  rb2.ok and rb2.cites and #rb2.cites == 1 and vim.fs.normalize(rb2.cites[1].path) == vim.fs.normalize(a.path),
  vim.inspect(rb2.cites))

-- A colliding hand-made file: same number, bib type. Only possible outside the
-- API (the counter is shared), and then a guess would be wrong half the time.
local root = require('pkm').config.root_path
local clash = root .. '/03-Consolidated/' .. num_a .. '_bib_Clash.md'
write(clash, { '---', 'title: "Clash"', 'tags: []', '---', '', 'clash' })
index.invalidate(clash)
local rx = api.resolve(num_a)
check("a number held by two notes → refused",
  rx.ok == false, vim.inspect(rx))
check("…naming both holders",
  tostring(rx.error):find('note-' .. num_a, 1, true) ~= nil
    and tostring(rx.error):find('bib-' .. num_a, 1, true) ~= nil, vim.inspect(rx))
local rx2 = api.resolve('note[' .. num_a .. ']')
check("the explicit token still resolves under a clash",
  rx2.ok and vim.fs.normalize(rx2.path) == vim.fs.normalize(a.path), vim.inspect(rx2))
vim.fn.delete(clash)
index.invalidate(clash)

-- =============================================================================
print("\n== long strings and wikilinks ==")
-- =============================================================================
local bad_chunk  = 'return [[Ver [[0042_note_Alpha]] e mais.]]'
local good_chunk = 'return [==[Ver [[0042_note_Alpha]] e mais.]==]'
local deep_chunk = 'return [====[t[a[i]==] e [[x]]]====]'
check("a wikilink inside [[…]] breaks the chunk", loadstring(bad_chunk) == nil)
local gf = loadstring(good_chunk)
check("[==[…]==] keeps the wikilink intact",
  gf ~= nil and gf() == 'Ver [[0042_note_Alpha]] e mais.')
check("[==[…]==] breaks on a body containing ]==]",
  loadstring('return [==[t[a[i]==] e]==]') == nil)
local df = loadstring(deep_chunk)
check("[====[…]====] carries a body containing ]==]",
  df ~= nil and df() == 't[a[i]==] e [[x]]')

-- =============================================================================
print("\n== child sessions under the shipped init ==")
-- =============================================================================
local root2 = fresh_root()   -- with spaces, the real shape

-- A task file whose note body holds a wikilink, written the safe way.
local task_ok = vim.fn.tempname() .. '_task_ok.lua'
write(task_ok, {
  "local api = require('pkm.api')",
  "local n = api.create('note', { title = 'Wiki', by = 'claude',",
  "  body = [==[Ver [[0001_note_x]] — ção → fim]==] })",
  "local r = api.read(n.path)",
  "api.emit({ ok = n.ok, body = r.body, swapfile = vim.o.swapfile, title = 'ção → é' })",
})
local r1 = run({ nvim_exe, '-u', init_path, '-l', task_ok, '--', '--root=' .. root2 })
local j1 = last_json(r1.stdout) or {}
check("-l task: exit 0", r1.code == 0, 'code=' .. r1.code .. ' ' .. r1.stderr)
check("-l task: the wikilink body round-trips through create/read",
  type(j1.body) == 'string' and j1.body:find('[[0001_note_x]] — ção → fim', 1, true) ~= nil,
  vim.inspect(j1.body))
check("the shipped init turns swap files off", j1.swapfile == false, vim.inspect(j1.swapfile))
check("emit writes raw UTF-8 (no \\u escapes) on stdout",
  r1.stdout:find('"title":"ção → é"', 1, true) ~= nil, r1.stdout)

-- A Lua error: -l exits 1, -c luafile exits 0 (the trap the docs warn about).
local task_bad = vim.fn.tempname() .. '_task_bad.lua'
write(task_bad, { "require('pkm.api')", "error('boom-from-task')" })
local r2 = run({ nvim_exe, '-u', init_path, '-l', task_bad, '--', '--root=' .. root2 })
check("-l with a raised error → exit 1", r2.code == 1, 'code=' .. r2.code)
check("-l with a raised error → message on stderr",
  r2.stderr:find('boom-from-task', 1, true) ~= nil, r2.stderr)
local r3 = run({ nvim_exe, '--headless', '-u', init_path, '-c', 'luafile ' .. task_bad, '-c', 'qa!',
  '--', '--root=' .. root2 })
check("-c luafile with a raised error → exit 0 (why -l is recommended)", r3.code == 0, 'code=' .. r3.code)
check("-c luafile: the error is only on stderr",
  r3.stderr:find('boom-from-task', 1, true) ~= nil and r3.stdout == '', r3.stderr)
check("-c form: no E303 swap-file error for the --root buffer",
  not r3.stderr:find('E303', 1, true), r3.stderr)

local task_syn = vim.fn.tempname() .. '_task_syn.lua'
write(task_syn, { "local body = [[Ver [[0001_note_x]] e mais.]]" })
local r4 = run({ nvim_exe, '-u', init_path, '-l', task_syn, '--', '--root=' .. root2 })
check("-l with the wikilink syntax error → exit 1", r4.code == 1, 'code=' .. r4.code .. ' ' .. r4.stderr)

print(string.format("\n%s — %d failure(s)", failures == 0 and "PASS" or "FAIL", failures))
if failures > 0 then vim.cmd('cquit 1') end
