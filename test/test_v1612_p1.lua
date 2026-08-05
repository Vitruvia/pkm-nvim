-- test/test_v1612_p1.lua
-- Forced-save prompt (Near 5.1) — citing a note that is open in an *unmodified*
-- buffer used to leave that buffer's on-disk timestamp stale after the backlink
-- write, so a later user :w saw the plugin's write as an external change (W12)
-- and forced a w!/y-n prompt with nothing in conflict. The fix writes the
-- backlink THROUGH the buffer, re-stamping the timestamp. This proves the
-- observable guarantees of that fix: the backlink is synced into the buffer AND
-- to disk, the buffer is left unmodified and in step with disk, a subsequent :w
-- is clean, and checktime finds no phantom external change. It also proves the
-- MODIFIED-buffer branch is unchanged (in-buffer only, no disk write).
--
-- The interactive W12 prompt itself is only visible to a human at a real :w, so
-- the no-prompt outcome is confirmed by the author's smoke; here we assert the
-- mechanism that removes its cause.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1612_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function buf_lines(bufnr) return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) end
local function disk_lines(path) return vim.fn.readfile(path) end
local function has(lines, needle)
  for _, l in ipairs(lines) do if l:find(needle, 1, true) then return true end end
  return false
end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api     = require('pkm.api')
local bufsync = require('pkm.bufsync')

local citing = api.create('note', { title = 'Citing note', by = 'claude', body = 'leans on the target.' })
local target = api.create('note', { title = 'Target note', by = 'claude', body = 'the target body.' })
check("both notes were created", citing.ok and target.ok, vim.inspect({ citing, target }))
local citing_id = string.format('note-%04d', citing.number)

print("== citing into an UNMODIFIED open buffer syncs it and leaves it clean ==")
vim.cmd('edit ' .. vim.fn.fnameescape(target.path))
local bufT = vim.api.nvim_get_current_buf()
check("the target is open and unmodified before the citation",
  bufsync.buffer_for(target.path) == bufT and vim.bo[bufT].modified == false)

local r = api.cite(citing.path, target.path)
check("api.cite returned ok", r.ok, vim.inspect(r))

check("the backlink reached the target's BUFFER", has(buf_lines(bufT), citing_id),
  vim.inspect(buf_lines(bufT)))
check("the backlink reached the target's DISK file", has(disk_lines(target.path), citing_id),
  vim.inspect(disk_lines(target.path)))
check("the buffer is left UNMODIFIED (written through, not left dirty)",
  vim.bo[bufT].modified == false, 'modified=' .. tostring(vim.bo[bufT].modified))
check("the buffer content matches disk exactly (in step)",
  same(buf_lines(bufT), disk_lines(target.path)),
  vim.inspect({ buf = buf_lines(bufT), disk = disk_lines(target.path) }))

-- The crux: Neovim's stored timestamp for the buffer must match the file it just
-- wrote, so nothing reports an external change. If the old code path (writefile
-- behind the buffer) were still in place, the file's mtime could sit ahead of
-- the buffer's record and checktime would fire FileChangedShell here.
local fired = false
local grp = vim.api.nvim_create_augroup('pkm_v1612_probe', { clear = true })
vim.api.nvim_create_autocmd('FileChangedShell', {
  group = grp, buffer = bufT, callback = function() fired = true end,
})
vim.cmd('checktime ' .. bufT)
check("checktime finds no phantom external change on the cited buffer", fired == false)

-- And a real save is clean and does not re-dirty anything.
local wrote_ok = pcall(function()
  vim.api.nvim_buf_call(bufT, function() vim.cmd('silent write') end)
end)
check("a subsequent :w on the cited buffer succeeds without error", wrote_ok)
check("the buffer is still unmodified after that :w", vim.bo[bufT].modified == false)

print("\n== the MODIFIED-buffer branch is unchanged: in-buffer only, no disk write ==")
local target2 = api.create('note', { title = 'Target two', by = 'claude', body = 'second target.' })
vim.cmd('edit ' .. vim.fn.fnameescape(target2.path))
local bufT2 = vim.api.nvim_get_current_buf()
-- Make it modified with an edit the citation must not discard.
vim.api.nvim_buf_set_lines(bufT2, -1, -1, false, { 'an unsaved edit line' })
check("target two is open WITH unsaved changes before the citation", vim.bo[bufT2].modified == true)

local r2 = api.cite(citing.path, target2.path)
check("api.cite returned ok (modified target)", r2.ok, vim.inspect(r2))
check("the backlink was applied in the modified BUFFER", has(buf_lines(bufT2), citing_id),
  vim.inspect(buf_lines(bufT2)))
check("the user's unsaved edit line is preserved", has(buf_lines(bufT2), 'an unsaved edit line'))
check("the buffer is STILL modified (nothing was written for it)", vim.bo[bufT2].modified == true)
check("the backlink did NOT reach disk (no write behind unsaved edits)",
  not has(disk_lines(target2.path), citing_id), vim.inspect(disk_lines(target2.path)))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
