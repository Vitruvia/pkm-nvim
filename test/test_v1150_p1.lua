-- test/test_v1150_p1.lua
-- v1.15.0 Ph1 — the global next-header (`:PKMHeader sibling`).
--
-- Unlike `:PKMHeader append` (current line +1, at EOF), `sibling` finds the
-- cursor's header, takes the highest same-level same-prefix counter in the
-- enclosing block, and inserts `<prefix>-<max+1>` at the END of that block —
-- after every sibling and its sub-content, before the next shallower header (or
-- at EOF) — then moves the cursor there. All buffer-line work, so headless.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1150_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local function set_buf(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end
local function lines() return vim.api.nvim_buf_get_lines(0, 0, -1, false) end
local function line(n) return (lines())[n] end
local function has_line(text)
  for _, l in ipairs(lines()) do if l == text then return true end end
  return false
end

print("== the sibling verb is registered ==")
check("`:PKMHeader sibling` completes",
  vim.tbl_contains(vim.fn.getcompletion('PKMHeader ', 'cmdline'), 'sibling'))

print("\n== from any sibling, it adds max+1 before the next shallower header ==")

set_buf({ '# Top', '## header-1', 'text a', '## header-2', 'text b', '# Higher', 'more' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })   -- on header-1 (m=1, but n=2)
vim.cmd('PKMHeader sibling')
check("it created ## header-3 (max+1, not current+1)", has_line('## header-3'),
  vim.inspect(lines()))
check("placed inside the h1 section, before '# Higher'", (function()
  local ls = lines()
  local hi, hh = nil, nil
  for i, l in ipairs(ls) do
    if l == '## header-3' then hh = i end
    if l == '# Higher' then hi = i end
  end
  return hh and hi and hh < hi
end)(), vim.inspect(lines()))
check("the cursor is on the new header", line(vim.api.nvim_win_get_cursor(0)[1]) == '## header-3',
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

print("\n== with no shallower header after, it lands at EOF ==")

set_buf({ '## a-1', 'x', '## a-2', 'y' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('PKMHeader sibling')
check("## a-3 was created", has_line('## a-3'), vim.inspect(lines()))
check("and it is the last non-blank line", (function()
  local ls = lines()
  for i = #ls, 1, -1 do if ls[i] ~= '' then return ls[i] == '## a-3' end end
  return false
end)(), vim.inspect(lines()))

print("\n== deeper sub-content is skipped, does not disturb the counter ==")

set_buf({ '## a-1', '### a-1-sub', 'deep', '## a-2' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('PKMHeader sibling')
check("still ## a-3 (the ### is not counted)", has_line('## a-3') and not has_line('## a-4'),
  vim.inspect(lines()))

print("\n== a header with no -N counter is refused, buffer untouched ==")

set_buf({ '## Intro', 'body' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local before = #lines()
local msg
local orig = vim.notify
vim.notify = function(m) msg = m end
vim.cmd('PKMHeader sibling')
vim.notify = orig
check("nothing was inserted", #lines() == before)
check("and it says why", type(msg) == 'string' and msg:find('counter', 1, true) ~= nil, tostring(msg))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
