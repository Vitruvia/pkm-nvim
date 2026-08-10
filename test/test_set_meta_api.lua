-- test/test_set_meta_api.lua
-- Post-hoc metadata setters (Gestor request #2): pkm.api.set_title and
-- pkm.api.set_source_meta. Title/source_author/source_type were create-only, so
-- a correction meant uncite → delete → recreate (destructive to numbering and
-- the graph). These setters write frontmatter on disk by ref, keep any open
-- buffer in step (write-through, no phantom W12 :w prompt), and — for the title
-- — propagate the new value to every note that cites this one.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_set_meta_api.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local yaml = require('pkm.yaml')
local function fm_of(path) return (yaml.parse_frontmatter(vim.fn.readfile(path))) end
local function buf_lines(b) return vim.api.nvim_buf_get_lines(b, 0, -1, false) end
local function disk_lines(p) return vim.fn.readfile(p) end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local pkm  = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

print("== set_title on a note that is not open writes disk ==")
local n = api.create('note', { title = 'Old Title', by = 'claude' })
check("note created", n.ok, vim.inspect(n))
check("disk title is the created one", fm_of(n.path).title == 'Old Title')
local r = api.set_title(n.path, 'Fresh Title')
check("api.set_title returned ok", r.ok, vim.inspect(r))
check("disk title is now the new one", fm_of(n.path).title == 'Fresh Title',
  vim.inspect(fm_of(n.path).title))

print("\n== set_title propagates to a note that cites this one ==")
local target = api.create('note', { title = 'Cited Note', by = 'claude' })
local citing = api.create('note', { title = 'Citing Note', by = 'claude', body = 'leans on it.' })
local c = api.cite(citing.path, target.path)
check("citation established", c.ok, vim.inspect(c))
local before = fm_of(citing.path)
check("citing note cached the old title",
  before.cites and before.cites.notes and before.cites.notes[1]
    and before.cites.notes[1].title == 'Cited Note',
  vim.inspect(before.cites))

local r2 = api.set_title(target.path, 'Retitled Note')
check("api.set_title (cited) ok", r2.ok, vim.inspect(r2))
local after = fm_of(citing.path)
check("the citing note's cached title was propagated",
  after.cites and after.cites.notes and after.cites.notes[1]
    and after.cites.notes[1].title == 'Retitled Note',
  vim.inspect(after.cites))

print("\n== set_title through an open, UNMODIFIED buffer leaves it clean ==")
local m = api.create('note', { title = 'Buffered', by = 'claude' })
vim.cmd('edit ' .. vim.fn.fnameescape(m.path))
local buf = vim.api.nvim_get_current_buf()
check("buffer open and unmodified before set_title", vim.bo[buf].modified == false)
local r3 = api.set_title(m.path, 'Buffered New')
check("api.set_title (buffered) ok", r3.ok, vim.inspect(r3))
local buf_fm = yaml.parse_frontmatter(buf_lines(buf))
check("the new title reached the BUFFER",
  buf_fm and buf_fm.title == 'Buffered New', vim.inspect(buf_lines(buf)))
check("buffer left UNMODIFIED (written through)", vim.bo[buf].modified == false)
check("buffer content matches disk exactly", same(buf_lines(buf), disk_lines(m.path)))
local fired = false
local grp = vim.api.nvim_create_augroup('pkm_setmeta_probe', { clear = true })
vim.api.nvim_create_autocmd('FileChangedShell', {
  group = grp, buffer = buf, callback = function() fired = true end })
vim.cmd('checktime ' .. buf)
check("checktime finds no phantom external change", fired == false)

print("\n== set_title is idempotent and validates the ref ==")
local r4 = api.set_title(m.path, 'Buffered New')  -- same value
check("setting the same title is a no-op success", r4.ok, vim.inspect(r4))
local r5 = api.set_title('note-9999', 'nope')
check("a bad ref is a clean failure", r5.ok == false and r5.error ~= nil, vim.inspect(r5))

print("\n== set_source_meta on a bib note ==")
local bib = api.create('bib', { title = 'A Source', by = 'claude' })
check("bib note created", bib.ok, vim.inspect(bib))
local s = api.set_source_meta(bib.path, { author = 'Kant', type = 'book' })
check("api.set_source_meta ok", s.ok, vim.inspect(s))
check("source_author written", fm_of(bib.path).source_author == 'Kant',
  vim.inspect(fm_of(bib.path).source_author))
check("source_type written", fm_of(bib.path).source_type == 'book',
  vim.inspect(fm_of(bib.path).source_type))
-- Partial update touches only the key given.
local s2 = api.set_source_meta(bib.path, { author = 'Hume' })
check("partial update ok", s2.ok, vim.inspect(s2))
check("source_author updated", fm_of(bib.path).source_author == 'Hume')
check("source_type left intact by the partial update", fm_of(bib.path).source_type == 'book')

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
