-- test/test_v1850_p1.lua
-- v1.85.0 Phase 1 — headless init + fail-early when pkm-markdown is missing
-- (dev-report from the ferramentas-concursos consumer, item P1).
--
-- The skill's minimal init put only pkm-nvim on the runtimepath. `create`/`find`/
-- `read` worked; `insert_section`/`cite_source` then crashed with `ipairs` over
-- nil, because `scan_headings` lives in the pkm-markdown sibling and the facade
-- degrades to a no-op returning nil. This phase:
--   * `pkm.markdown.available()` — a real facade key reporting the backend;
--   * `notes.write_section` refuses with a message naming pkm-markdown instead
--     of crashing (so insert_section / cite_source / annotate(heading) do too);
--   * `api.health()` — the preflight naming the gap up front;
--   * `scripts/headless_init.lua` — mounts the three plugins, requires --root,
--     and exits 1 on an incomplete session.
--
-- The missing-sibling case cannot be staged in-process (min_init mounts the
-- siblings and the facade caches its backend), so it runs in a CHILD nvim with a
-- bare init — the exact shape the consumer reported.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1850_p1.lua" -c "qa!"

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

-- Run a child nvim; returns { code, stdout, stderr }.
local function run(args)
  local res = vim.system(args, { text = true }):wait(60000)
  return { code = res.code, stdout = res.stdout or '', stderr = res.stderr or '' }
end

-- The last JSON line a child emitted on stdout, decoded (nil if none).
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

-- A fresh vault root with a consolidated folder.
local function fresh_root()
  local r = vim.fn.tempname() .. '/Note-Vault/00 - Test'
  vim.fn.mkdir(r .. '/03-Consolidated', 'p')
  return r
end

-- =============================================================================
print("== in-process (min_init mounts all three plugins) ==")
-- =============================================================================
local api = require('pkm.api')
check("markdown.available() is true with the sibling mounted",
  require('pkm.markdown').available() == true)
local h = api.health()
check("health().ok", h.ok == true, vim.inspect(h))
check("health().markdown and .syntax", h.markdown == true and h.syntax == true, vim.inspect(h))
check("health() is JSON-encodable", pcall(vim.json.encode, h))

-- =============================================================================
print("\n== child with a BARE init (pkm-nvim only) — the reported shape ==")
-- =============================================================================
local bare_root = fresh_root()
local bare_init = vim.fn.tempname() .. '_bare_init.lua'
write(bare_init, {
  "vim.opt.runtimepath:prepend(" .. vim.inspect(repo_root) .. ")",
  "vim.o.shadafile = 'NONE'",
  "require('pkm').setup({ root_path = " .. vim.inspect(bare_root) .. " })",
})
local bare_task = vim.fn.tempname() .. '_bare_task.lua'
write(bare_task, {
  "local api = require('pkm.api')",
  "local n = api.create('note', { title = 'Bare', by = 'claude', body = '## Notes\\n\\nfirst' })",
  "local before = table.concat(vim.fn.readfile(n.path), '\\n')",
  "local ok1, s = pcall(api.insert_section, n.path, 'Notes', 'second')",
  "local ok2, c = pcall(api.cite_source, n.path, { title = 'Some Book', bibtex = '@book{x}' })",
  "local after = table.concat(vim.fn.readfile(n.path), '\\n')",
  "api.emit({ created = n.ok, health = api.health(), avail = require('pkm.markdown').available(),",
  "  ins_raised = not ok1, ins = ok1 and s or tostring(s),",
  "  cite_raised = not ok2, cite = ok2 and c or tostring(c), unchanged = (before == after) })",
})
local r = run({ nvim_exe, '--headless', '-u', bare_init, '-c', 'luafile ' .. bare_task, '-c', 'qa!' })
local j = last_json(r.stdout)
check("child emitted a JSON result", j ~= nil, r.stdout .. ' | ' .. r.stderr)
j = j or {}
check("create still works without pkm-markdown (the misleading half)", j.created == true)
check("markdown.available() is false there", j.avail == false, vim.inspect(j.avail))
check("health().ok is false and names pkm-markdown",
  j.health and j.health.ok == false and j.health.markdown == false
    and table.concat(j.health.errors or {}, ' '):find('pkm-markdown', 1, true) ~= nil,
  vim.inspect(j.health))
check("insert_section did NOT raise (no ipairs-over-nil crash)", j.ins_raised == false, vim.inspect(j.ins))
check("insert_section refused with ok=false",
  type(j.ins) == 'table' and j.ins.ok == false, vim.inspect(j.ins))
check("insert_section's error names pkm-markdown",
  type(j.ins) == 'table' and tostring(j.ins.error):find('pkm-markdown', 1, true) ~= nil,
  vim.inspect(j.ins))
check("cite_source did NOT raise", j.cite_raised == false, vim.inspect(j.cite))
check("cite_source refused with an error naming pkm-markdown",
  type(j.cite) == 'table' and j.cite.ok == false
    and tostring(j.cite.error):find('pkm-markdown', 1, true) ~= nil,
  vim.inspect(j.cite))
check("the note was left untouched by the refused writes", j.unchanged == true)
check("no Lua traceback in the child's stderr",
  not r.stderr:find('stack traceback', 1, true) and not r.stderr:find('E5108', 1, true), r.stderr)

-- =============================================================================
print("\n== scripts/headless_init.lua ==")
-- =============================================================================
check("the init file exists", vim.fn.filereadable(init_path) == 1, init_path)

local r1 = run({ nvim_exe, '--headless', '-u', init_path, '-c', 'qa!' })
check("no --root → exit status 1", r1.code == 1, 'code=' .. tostring(r1.code))
check("no --root → stderr says --root is required",
  r1.stderr:find('--root=<path> is required', 1, true) ~= nil, r1.stderr)

local missing = vim.fn.tempname() .. '/does-not-exist'
local r2 = run({ nvim_exe, '--headless', '-u', init_path, '-c', 'qa!', '--', '--root=' .. missing })
check("nonexistent --root → exit status 1", r2.code == 1, 'code=' .. tostring(r2.code))
check("nonexistent --root → stderr names it",
  r2.stderr:find('not an existing directory', 1, true) ~= nil, r2.stderr)

local empty_suite = vim.fn.tempname() .. '_empty_suite'
vim.fn.mkdir(empty_suite, 'p')
local good_root = fresh_root()
local r3 = run({ nvim_exe, '--headless', '-u', init_path, '-c', 'qa!', '--',
  '--root=' .. good_root, '--pkm-suite=' .. empty_suite })
check("--pkm-suite without the siblings → exit status 1", r3.code == 1, 'code=' .. tostring(r3.code))
check("--pkm-suite without the siblings → stderr names pkm-markdown",
  r3.stderr:find('pkm-markdown not found', 1, true) ~= nil, r3.stderr)

-- A vault path WITH SPACES (the real shape), passed as one quoted argv item.
local good_task = vim.fn.tempname() .. '_good_task.lua'
write(good_task, {
  "local api = require('pkm.api')",
  "local n = api.create('note', { title = 'Full', by = 'claude', body = '## Notes\\n\\nfirst' })",
  "local s = api.insert_section(n.path, 'Notes', 'second')",
  "local body = table.concat(vim.fn.readfile(n.path), '\\n')",
  "api.emit({ health = api.health(), ins = s, has_second = body:find('second', 1, true) ~= nil,",
  "  root = require('pkm').config.root_path })",
})
local r4 = run({ nvim_exe, '--headless', '-u', init_path, '-c', 'luafile ' .. good_task, '-c', 'qa!',
  '--', '--root=' .. good_root })
local j4 = last_json(r4.stdout) or {}
check("valid --root → exit status 0", r4.code == 0, 'code=' .. tostring(r4.code) .. ' ' .. r4.stderr)
check("valid --root → health ok with markdown + syntax",
  j4.health and j4.health.ok == true and j4.health.markdown == true and j4.health.syntax == true,
  vim.inspect(j4.health))
check("the session operates on the given root (path with spaces intact)",
  j4.root and vim.fs.normalize(j4.root) == vim.fs.normalize(good_root), vim.inspect(j4.root))
check("insert_section works under the official init",
  j4.ins and j4.ins.ok == true and j4.has_second == true, vim.inspect(j4.ins))

print(string.format("\n%s — %d failure(s)", failures == 0 and "PASS" or "FAIL", failures))
if failures > 0 then vim.cmd('cquit 1') end
