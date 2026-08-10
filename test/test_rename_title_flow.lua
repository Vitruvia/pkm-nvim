-- test/test_rename_title_flow.lua
-- Regression for the smoke-found §3 bug (v1.66.0): after :PKMNote rename renamed
-- the file, changing the title left the buffer needing `:w!` — a plain `:w`
-- raised E13 ("File exists, add !"), and the write-through silently swallowed it
-- so the new title never reached disk. Root cause: nvim_buf_set_name leaves the
-- buffer in Vim's BF_NOTEDITED state, so any later write to the now-existing path
-- demands `!`. rename_file now forces one silent, autocmd-free write to normalise
-- the buffer's ownership and stamp its on-disk timestamp.
--
-- This proves the observable guarantees of the fix: after rename + set_title_at
-- the buffer is unmodified and matches disk, the new title IS on disk, a plain
-- `:w` succeeds without `!`, and checktime finds no phantom external change. It
-- also proves the latent pre-existing case (rename → genuine edit → plain `:w`)
-- is now clean.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_rename_title_flow.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end

local pkm  = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })
local api, notes, yaml = require('pkm.api'), require('pkm.notes'), require('pkm.yaml')

local function disk_title(p) local fm = yaml.parse_frontmatter(vim.fn.readfile(p)); return fm and fm.title end

print("== rename → set_title_at → plain :w is clean (the §3 guarantee) ==")
local n = api.create('note', { title = 'Orig', by = 'claude', body = 'body.' })
vim.cmd('edit ' .. vim.fn.fnameescape(n.path))
local buf = vim.api.nvim_get_current_buf()

local r = api.rename(n.path, 'Renamed Note')
check("rename ok and marker preserved",
  r.ok and vim.fn.fnamemodify(r.path, ':t'):match('^%d+_note_ByClaude_Renamed_Note%.md$'),
  r.path)
check("buffer is unmodified right after rename", vim.bo[buf].modified == false)

local ok = notes.set_title_at(r.path, 'A New Title')
check("set_title_at ok", ok)
check("the new title reached DISK (write-through was not swallowed)",
  disk_title(r.path) == 'A New Title', tostring(disk_title(r.path)))
check("buffer left UNMODIFIED after the title write-through", vim.bo[buf].modified == false)

-- The crux: a plain :w must succeed, no E13/`!`, and re-dirty nothing.
local wok, werr = pcall(function() vim.api.nvim_buf_call(buf, function() vim.cmd('write') end) end)
check("a plain :w succeeds without needing `!` (no E13)", wok, tostring(werr))
check("still unmodified after :w", vim.bo[buf].modified == false)

local fired = false
local grp = vim.api.nvim_create_augroup('pkm_renametitle_probe', { clear = true })
vim.api.nvim_create_autocmd('FileChangedShell', { group = grp, buffer = buf, callback = function() fired = true end })
vim.cmd('checktime ' .. buf)
check("checktime finds no phantom external change (no W12)", fired == false)

print("\n== latent case: rename → genuine edit → plain :w is clean ==")
local n2 = api.create('note', { title = 'Two', by = 'claude', body = 'b.' })
vim.cmd('edit ' .. vim.fn.fnameescape(n2.path))
local buf2 = vim.api.nvim_get_current_buf()
local r2 = api.rename(n2.path, 'Two Renamed')
vim.api.nvim_buf_set_lines(buf2, -1, -1, false, { 'a genuine user edit' })
check("buffer is modified after the edit", vim.bo[buf2].modified == true)
local w2 = pcall(function() vim.api.nvim_buf_call(buf2, function() vim.cmd('write') end) end)
check("a plain :w after rename+edit succeeds without `!`", w2)
check("the user edit reached disk", (function()
  for _, l in ipairs(vim.fn.readfile(r2.path)) do if l == 'a genuine user edit' then return true end end
  return false end)())

print("\n== the ARGUMENT form of :PKMNote rename is deterministic: no title prompt ==")
-- rename_note('name') is the argument form (`:PKMNote rename name`). It must NOT
-- open the interactive title prompt — that would block a headless/scripted run
-- (this very test would hang) and break the "arguments = script-callable"
-- contract. Only the bare form (rename_note(nil), name typed at the prompt) may
-- offer the title. This call simply RETURNING is half the proof; the title
-- staying untouched is the other half.
local n3 = api.create('note', { title = 'Keep This Title', by = 'claude', body = 'x.' })
vim.cmd('edit ' .. vim.fn.fnameescape(n3.path))
notes.rename_note('Arg Renamed Note')
local p3 = vim.fn.expand('%:p')
check("arg-form rename renamed the file and kept the marker",
  p3:match('0%d+_note_ByClaude_Arg_Renamed_Note%.md$'), vim.fn.fnamemodify(p3, ':t'))
check("arg-form rename left the title untouched (no prompt fired)",
  disk_title(p3) == 'Keep This Title', tostring(disk_title(p3)))

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
