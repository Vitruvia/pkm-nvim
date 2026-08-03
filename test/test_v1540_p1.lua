-- test/test_v1540_p1.lua
-- v1.54.0 — buffer panel additions (author notes):
--   A. `/` opens a fuzzy pop-up over the open buffers; choosing one opens it in
--      a real editing window (like the sidebar's search, for when there are too
--      many buffers to scan). Driven through the real keymap with vim.ui.select
--      stubbed (no Telescope headless).
--   B. `[count]<CR>` opens the buffer under the cursor in the Nth editing window
--      (mirrors the view sidebar); a bare <CR> lands in a real editing window;
--      a count past the last window notifies rather than doing nothing.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1540_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local pkm   = require('pkm')
local utils = require('pkm.utils')
local yaml  = require('pkm.yaml')
local index = require('pkm.index')
local ui    = require('pkm.ui')

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')
local function make(stem)
  local lines = { '---' }
  vim.list_extend(lines, yaml.generate_yaml({ title = 'Note ' .. stem, tags = {} }))
  vim.list_extend(lines, { '---', '', 'body' })
  local p = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, p)
  return p
end
local p1 = make('1541_alpha_one')
local p2 = make('1542_beta_one')
index.rebuild()

-- Two listed buffers in the main window.
vim.cmd('edit ' .. vim.fn.fnameescape(p1))
vim.cmd('edit ' .. vim.fn.fnameescape(p2))

local function bufpanel_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'pkm-bufpanel' then return w end
  end
end

print("== A. '/' opens a pop-up of the open buffers; choosing one opens it ==")
if not ui.is_bufpanel_open() then ui.toggle_bufpanel() end   -- PKM mode may have opened it
vim.wait(300, function() return ui.is_bufpanel_open() end, 10)
local bpw = bufpanel_win()
check("buffer panel open", bpw ~= nil)

local orig = vim.ui.select
local offered
vim.ui.select = function(items, _opts, cb)
  offered = {}
  for _, it in ipairs(items) do offered[#offered + 1] = vim.api.nvim_buf_get_name(it.value) end
  for _, it in ipairs(items) do
    if vim.api.nvim_buf_get_name(it.value):find('1541_alpha_one', 1, true) then cb(it); return end
  end
  cb(nil)
end
vim.api.nvim_set_current_win(bpw)
feed('/')
vim.wait(300, function() return vim.api.nvim_buf_get_name(0):find('1541_alpha_one', 1, true) ~= nil end, 10)
vim.ui.select = orig

check("'/' offered the open buffers (both)",
  offered ~= nil and #offered >= 2, offered and (#offered .. '') or 'nil')
check("choosing a buffer opened it in an editing window (not the panel)",
  vim.bo.filetype ~= 'pkm-bufpanel'
  and vim.api.nvim_buf_get_name(0):find('1541_alpha_one', 1, true) ~= nil,
  vim.api.nvim_buf_get_name(0))

print("\n== B. <CR> lands in an editing window; a too-large count notifies ==")
if not ui.is_bufpanel_open() then ui.toggle_bufpanel() end
vim.wait(300, function() return ui.is_bufpanel_open() end, 10)
bpw = bufpanel_win()

vim.api.nvim_set_current_win(bpw)
vim.api.nvim_win_set_cursor(bpw, { 2, 0 })          -- first buffer row
feed('<CR>')
check("bare <CR> opened the row's buffer in an editing window",
  vim.bo.filetype ~= 'pkm-bufpanel' and vim.api.nvim_buf_get_name(0) ~= '',
  vim.bo.filetype .. ' / ' .. vim.api.nvim_buf_get_name(0))

if not ui.is_bufpanel_open() then ui.toggle_bufpanel() end
vim.wait(300, function() return ui.is_bufpanel_open() end, 10)
bpw = bufpanel_win()
local msgs = {}
local orig_notify = vim.notify
vim.notify = function(m) msgs[#msgs + 1] = m end
vim.api.nvim_set_current_win(bpw)
vim.api.nvim_win_set_cursor(bpw, { 2, 0 })
feed('9<CR>')                                        -- count past the last window
vim.notify = orig_notify
check("[count]<CR> past the last editing window notifies", (function()
  for _, m in ipairs(msgs) do
    if type(m) == 'string' and m:find('no window 9', 1, true) then return true end
  end
  return false
end)(), table.concat(vim.tbl_map(tostring, msgs), ' | '))

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
