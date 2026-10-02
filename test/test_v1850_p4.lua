-- test/test_v1850_p4.lua
-- v1.85.0 Phase 4 — checked batch writes: preview, compare-and-swap,
-- all-or-nothing, history (dev-report from the ferramentas-concursos consumer,
-- item P4).
--
-- The consumer's apply_changes.lua wrote the student's notes with io.open
-- because the API had no preview/diff of N notes, no hash precondition, no
-- all-at-once apply and no history — and paid for it: graph not reconciled,
-- last_updated_on frozen, no author. `api.write_notes` / `write_notes_preview`
-- / `file_sha`, and `set_body(path, content, opts)`, close that.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1850_p4.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local api  = require('pkm.api')
local yaml = require('pkm.yaml')
local root = require('pkm').config.root_path

local function bytes(p)
  local f = io.open(p, 'rb'); local d = f:read('*a'); f:close(); return d
end
local function fm_of(p) return (yaml.parse_frontmatter(vim.fn.readfile(p))) end
local function body_of(p)
  local lines = vim.fn.readfile(p)
  local _, cs = yaml.parse_frontmatter(lines)
  local out = {}
  for i = cs, #lines do out[#out + 1] = lines[i] end
  return table.concat(out, '\n')
end
-- Age a note's last_updated_on, so "it was stamped" cannot pass by the clock
-- simply not having moved since creation.
local function age(p)
  local lines = vim.fn.readfile(p)
  local fm, cs = yaml.parse_frontmatter(lines)
  fm.last_updated_on = '2000-01-01T00:00:00'
  yaml.save_frontmatter(fm, cs, p)
end
local function history_files()
  local dir = root .. '/.pkm-history'
  if vim.fn.isdirectory(dir) == 0 then return {} end
  local out = vim.fn.readdir(dir)
  table.sort(out)
  return out
end

local A = api.create('note', { title = 'Batch A', by = 'claude', body = 'alpha original' })
local B = api.create('note', { title = 'Batch B', by = 'claude', body = 'beta original' })
local C = api.create('note', { title = 'Batch C', by = 'claude', body = 'gamma' })
check("notes created", A.ok and B.ok and C.ok)
age(A.path); age(B.path)

-- =============================================================================
print("== file_sha ==")
-- =============================================================================
check("file_sha = sha256 of the file's bytes", api.file_sha(A.path) == vim.fn.sha256(bytes(A.path)))
check("file_sha of a missing file = nil", api.file_sha(root .. '/nope.md') == nil)

-- =============================================================================
print("\n== preview ==")
-- =============================================================================
local shaA, shaB = api.file_sha(A.path), api.file_sha(B.path)
local pv = api.write_notes_preview({
  { path = A.path, body = 'alpha REWRITTEN', expected_sha = shaA },
  { path = B.path, body = body_of(B.path):gsub('^\n', '') },   -- the same body
})
check("preview ok, dry_run", pv.ok and pv.dry_run == true, vim.inspect(pv.error))
check("preview: A changed, with a unified diff",
  pv.notes[1].changed == true and pv.notes[1].diff:find('+alpha REWRITTEN', 1, true) ~= nil
    and pv.notes[1].diff:find('-alpha original', 1, true) ~= nil, vim.inspect(pv.notes[1]))
check("preview: B unchanged (same body)", pv.notes[2].changed == false and pv.unchanged == 1,
  vim.inspect(pv.notes[2]))
check("preview reports sha_before", pv.notes[1].sha_before == shaA)
check("preview wrote nothing", api.file_sha(A.path) == shaA and api.file_sha(B.path) == shaB)
check("preview is JSON-encodable", pcall(vim.json.encode, pv))

-- =============================================================================
print("\n== all or nothing ==")
-- =============================================================================
local r1 = api.write_notes({
  { path = A.path, body = 'alpha REWRITTEN', expected_sha = shaA },
  { path = B.path, body = 'beta REWRITTEN',  expected_sha = string.rep('0', 64) },   -- stale
})
check("a stale expected_sha refuses the batch",
  r1.ok == false and r1.written == 0 and tostring(r1.error):find('sha mismatch', 1, true) ~= nil,
  vim.inspect(r1.error))
check("…the conflict is on B", r1.notes[2].error ~= nil and r1.notes[1].error == nil)
-- The reading to exclude: "the good entry went through before the bad one".
check("…and A, listed FIRST, was not written", api.file_sha(A.path) == shaA)

local r2 = api.write_notes({ { path = A.path, body = 'x' }, { path = A.path, body = 'y' } })
check("the same note twice is refused", r2.ok == false and api.file_sha(A.path) == shaA, vim.inspect(r2.error))

local r3 = api.write_notes({ { path = A.path, body = 'x', content = 'y' } })
check("body AND content in one entry is refused", r3.ok == false)

-- An unsaved buffer in this session.
vim.cmd('edit ' .. vim.fn.fnameescape(B.path))
vim.api.nvim_buf_set_lines(0, -1, -1, false, { 'unsaved' })
local r4 = api.write_notes({ { path = A.path, body = 'alpha REWRITTEN' }, { path = B.path, body = 'b2' } })
check("a note with unsaved edits here refuses the batch",
  r4.ok == false and tostring(r4.error):find('unsaved', 1, true) ~= nil and api.file_sha(A.path) == shaA,
  vim.inspect(r4.error))
vim.cmd('bwipeout!')

-- =============================================================================
print("\n== apply ==")
-- =============================================================================
local before_hist = #history_files()
local r5 = api.write_notes({
  { path = A.path, body = 'alpha REWRITTEN, citing [note[' .. string.format('%04d', C.number) .. ']]',
    expected_sha = shaA },
  { path = B.path, body = 'beta REWRITTEN', expected_sha = shaB },
}, { by = 'claude' })
check("the batch applies", r5.ok == true and r5.written == 2, vim.inspect(r5.error))
check("bodies written", body_of(A.path):find('alpha REWRITTEN', 1, true) ~= nil
  and body_of(B.path):find('beta REWRITTEN', 1, true) ~= nil)
local fa = fm_of(A.path)
check("frontmatter kept (title)", fa.title == 'Batch A', vim.inspect(fa.title))
check("last_updated_on stamped", fa.last_updated_on ~= '2000-01-01T00:00:00'
  and fm_of(B.path).last_updated_on ~= '2000-01-01T00:00:00', vim.inspect(fa.last_updated_on))
local ra = api.read(A.path)
check("graph reconciled: A cites C",
  ra.cites and #ra.cites == 1 and vim.fs.normalize(ra.cites[1].path) == vim.fs.normalize(C.path),
  vim.inspect(ra.cites))
local rc = api.read(C.path)
check("…and C has the backlink", rc.cited_by and #rc.cited_by == 1, vim.inspect(rc.cited_by))
check("sha_after reported = the file now",
  r5.notes[1].sha_after == api.file_sha(A.path) and r5.notes[1].sha_before == shaA)

local hist = history_files()
check("one history entry recorded", #hist == before_hist + 1 and r5.history ~= nil, vim.inspect(hist))
local h = vim.json.decode(bytes(root .. '/' .. r5.history))
check("history: author and two notes", h.by == 'claude' and #h.notes == 2, vim.inspect(h.by))
check("history: paths relative to the root (no absolute path in vault state)",
  h.notes[1].path:match('^03%-Consolidated/') ~= nil and not h.notes[1].path:find(':', 1, true),
  h.notes[1].path)
check("history: the previous text, byte for byte", vim.fn.sha256(h.notes[1].before) == shaA)

-- =============================================================================
print("\n== content mode (an edited copy of the whole file) ==")
-- =============================================================================
local cur = bytes(B.path)
local sha_cur = vim.fn.sha256(cur)
local edited = cur:gsub('beta REWRITTEN', 'beta FROM COPY')
local r6 = api.write_notes({ { path = B.path, content = edited, expected_sha = sha_cur } })
check("a copy with only the body edited applies", r6.ok == true and r6.written == 1, vim.inspect(r6.error))
check("…its body is the copy's", body_of(B.path):find('beta FROM COPY', 1, true) ~= nil)
local cur2 = bytes(B.path)
local touched = cur2:gsub('title: "Batch B"', 'title: "Hacked"'):gsub('beta FROM COPY', 'beta AGAIN')
local r7 = api.write_notes({ { path = B.path, content = touched } })
check("a copy that changed the frontmatter is refused",
  r7.ok == false and tostring(r7.error):find('frontmatter', 1, true) ~= nil, vim.inspect(r7.error))
check("…and nothing was written", bytes(B.path) == cur2)

-- =============================================================================
print("\n== rollback ==")
-- =============================================================================
local D = api.create('note', { title = 'Batch D', by = 'claude', body = 'delta' })
local a_before, b_before, d_before = bytes(A.path), bytes(B.path), bytes(D.path)
vim.uv.fs_chmod(B.path, tonumber('444', 8))   -- B cannot be written
local r8 = api.write_notes({
  -- A is written first, and its new body adds an edge to D (a backlink on D).
  { path = A.path, body = 'A in a failing batch, citing [note[' .. string.format('%04d', D.number) .. ']]' },
  { path = B.path, body = 'B cannot be written' },
}, { history = false })
vim.uv.fs_chmod(B.path, tonumber('666', 8))
check("a write failure mid-batch → ok=false, rolled_back", r8.ok == false and r8.rolled_back == true,
  vim.inspect({ r8.error, r8.rolled_back }))
check("…A, already written, is restored byte for byte", bytes(A.path) == a_before)
-- The reading to exclude: "restoring A's bytes is the whole rollback" — the
-- backlink A's new body put on D must be gone too.
check("…the backlink A's failed body put on D is undone", bytes(D.path) == d_before
  and #(api.read(D.path).cited_by or {}) == 0, vim.inspect(api.read(D.path).cited_by))
check("…A still cites C (its pre-batch edge survives)", #(api.read(A.path).cites or {}) == 1)
check("…B is untouched", bytes(B.path) == b_before)

-- =============================================================================
print("\n== set_body(path, content, opts) ==")
-- =============================================================================
local s0 = api.file_sha(A.path)
local d = api.set_body(A.path, 'alpha via set_body', { dry_run = true })
check("set_body dry_run: diff, nothing written",
  d.ok and d.dry_run and d.changed and d.diff:find('+alpha via set_body', 1, true) ~= nil
    and api.file_sha(A.path) == s0, vim.inspect(d))
local x = api.set_body(A.path, 'alpha via set_body', { expected_sha = 'stale' })
check("set_body with a stale expected_sha refuses", x.ok == false and api.file_sha(A.path) == s0)
local n_hist = #history_files()
local w = api.set_body(A.path, 'alpha via set_body', { expected_sha = s0 })
check("set_body with the right sha writes", w.ok and body_of(A.path):find('alpha via set_body', 1, true) ~= nil,
  vim.inspect(w))
check("…without a history entry by default", #history_files() == n_hist)
local plain = api.set_body(A.path, 'plain write')
check("set_body without opts: the plain write, as before",
  plain.ok == true and plain.diff == nil and body_of(A.path):find('plain write', 1, true) ~= nil)

-- =============================================================================
print("\n== the cross-session guard applies to the batch ==")
-- =============================================================================
local inst = require('pkm.instances')
local addr = vim.fn.has('win32') == 1 and ([[\\.\pipe\pkm-test-p4-busy-]] .. vim.uv.os_getpid())
  or (vim.fn.tempname() .. '-busy.sock')
local busy = vim.system({ vim.v.progpath, '--clean', '--headless', '--listen', addr,
  '-c', 'lua vim.uv.sleep(6000)', '-c', 'qa!' })
vim.wait(1500)
vim.fn.mkdir(inst.dir(), 'p')
local bfile = inst.dir() .. '/' .. busy.pid .. '.json'
vim.fn.writefile({ vim.json.encode({ pid = busy.pid, server = addr }) }, bfile)
local s1 = api.file_sha(A.path)
local r9 = api.write_notes({ { path = A.path, body = 'blocked?' } }, { timeout = 600 })
check("a registered session that does not answer → the batch is refused",
  r9.ok == false and tostring(r9.error):find('did not answer', 1, true) ~= nil and api.file_sha(A.path) == s1,
  vim.inspect(r9.error))
busy:kill(9)
vim.fn.delete(bfile)

print(string.format("\n%s — %d failure(s)", failures == 0 and "PASS" or "FAIL", failures))
if failures > 0 then vim.cmd('cquit 1') end
