-- test/test_v1200_p1.lua
-- pkm.api.ui_state — the *inspect* half of agent-assisted smoke testing. It reads
-- the interactive UI as plain data: current buffer, whether the views sidebar and
-- buffer panel are open, and what the sidebar shows/highlights. Paired with
-- feedkeys driving the real mappings, it lets an agent assert that an interactive
-- path behaved — the part the headless unit suite cannot see. This test proves
-- both: ui_state reflects UI changes, and a real keymap driven by feedkeys moves
-- that state.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1200_p1.lua" -c "qa!"

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
pkm.setup({ root_path = root, projects = { ['Bars'] = 'tag:bar', ['Foos'] = 'tag:foo' } })

local api   = require('pkm.api')
local views = require('pkm.views')

local one = api.create('note', { title = 'One', by = 'claude', tags = { 'foo' } })
api.create('note', { title = 'Two', by = 'claude', tags = { 'bar' } })

print("== baseline: nothing open ==")
local s0 = api.ui_state()
check("ui_state returns a table", type(s0) == 'table', vim.inspect(s0))
check("the sidebar is reported closed", s0.sidebar.open == false, vim.inspect(s0.sidebar))
check("the buffer panel is reported closed", s0.bufpanel.open == false, vim.inspect(s0.bufpanel))
check("current carries a buffer handle", type(s0.current.buf) == 'number')

print("\n== open_sidebar(): ui_state shows it, with the highlighted view ==")
views.open_sidebar()
local s1 = api.ui_state()
check("the sidebar is now open", s1.sidebar.open == true, vim.inspect(s1.sidebar))
check("ui_state carries the sidebar's rendered lines",
  type(s1.sidebar.lines) == 'table' and #s1.sidebar.lines > 0, vim.inspect(s1.sidebar.lines))
check("a view is listed in the sidebar", (function()
  for _, l in ipairs(s1.sidebar.lines) do if l:find('Bars', 1, true) then return true end end
  return false
end)(), vim.inspect(s1.sidebar.lines))
check("highlighted_view is parsed from the cursor line",
  s1.sidebar.highlighted_view ~= nil and s1.sidebar.highlighted_view ~= '',
  vim.inspect({ hl = s1.sidebar.highlighted, view = s1.sidebar.highlighted_view }))

print("\n== a real keymap driven by feedkeys moves the state (the round-trip) ==")
-- Close it first (no-arg open_sidebar toggles), then reopen THROUGH the mapping.
views.open_sidebar()
check("sidebar closed again before the keystroke test", api.ui_state().sidebar.open == false)

-- Resolve <leader>vs to actual keys and feed them, exercising the real mapping
-- (`<leader>vs` → <cmd>PKMView sidebar<cr>), not a direct function call.
local leader = vim.g.mapleader
if leader == nil or leader == '' then leader = '\\' end
vim.api.nvim_feedkeys(leader .. 'vs', 'x', false)
local s2 = api.ui_state()
check("feeding <leader>vs opened the sidebar via the real mapping",
  s2.sidebar.open == true, vim.inspect(s2.sidebar))

print("\n== ui_state resolves the current note (title/type from the index) ==")
views.open_sidebar()  -- close it so the note buffer is current
vim.cmd('edit ' .. vim.fn.fnameescape(one.path))
local s3 = api.ui_state()
check("current.name is the opened note", s3.current.name == one.path, s3.current.name)
check("current.title comes from the index", s3.current.title == 'One', tostring(s3.current.title))
check("current.type is a consolidated note type",
  s3.current.type == 'note' or s3.current.type == 'agg' or s3.current.type == 'bib',
  tostring(s3.current.type))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
