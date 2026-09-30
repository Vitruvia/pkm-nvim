-- test/test_v160_p1.lua
-- Integration-style tests for v1.6.0 Phase 1: panel.lua generic lifecycle,
-- and the buffer-panel port. (The tag panel it also covered was retired in
-- v1.84.0 for the shared tag picker — see test/test_v1840_p1.lua.)
-- Not pure-logic (panel.lua is inherently side-effecting: real window/buffer
-- creation) — run against a real headless Neovim instance, per the Standing
-- Verification Protocol. What's asserted here is everything cleanly reachable
-- without simulating keypresses.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v160_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

-- ============================================================================
-- SECTION: panel.lua generic lifecycle (isolated throwaway panel)
-- ============================================================================

print("== panel.lua generic lifecycle ==")

do
  local panel = require('pkm.panel')
  local build_calls = 0

  local p = panel.create({
    name        = 'testpanel',
    split_cmd   = 'noautocmd botright split',
    build_lines = function(_)
      build_calls = build_calls + 1
      return { '  line one', '  line two' }, { [1] = 'a', [2] = 'b' }
    end,
  })

  check("is_open() false before any open()", p.is_open() == false)
  check("get_win() nil before any open()", p.get_win() == nil)

  p.open()
  check("is_open() true after open()", p.is_open() == true)
  local win = p.get_win()
  check("get_win() returns a valid window", win ~= nil and vim.api.nvim_win_is_valid(win))
  check("build_lines called on open", build_calls == 1)

  local buf = vim.api.nvim_win_get_buf(win)
  check("winfixbuf set on panel window",
    vim.api.nvim_get_option_value('winfixbuf', { win = win }) == true)
  check("filetype set correctly",
    vim.api.nvim_get_option_value('filetype', { buf = buf }) == 'pkm-testpanel')
  check("buffer content matches build_lines output",
    vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { '  line one', '  line two' }))

  p.refresh()
  check("build_lines called again on refresh", build_calls == 2)

  p.toggle()
  check("toggle() closes when open", p.is_open() == false)

  p.toggle()
  check("toggle() opens when closed", p.is_open() == true)
  check("build_lines called on toggle-open", build_calls == 3)  -- close() wipes
    -- state via BufWipeout, so this reopen takes the fresh-create path
    -- (one refresh() call inside), not the already-open reconfigure path

  p.close()
  check("is_open() false after close()", p.is_open() == false)
end

-- ============================================================================
-- SECTION: per-tab isolation
-- ============================================================================

print("== panel.lua per-tab isolation ==")

do
  local panel = require('pkm.panel')
  local p = panel.create({
    name        = 'testpanel2',
    split_cmd   = 'noautocmd botright split',
    build_lines = function(_) return { '  x' }, {} end,
  })

  p.open()
  check("open in tab 1", p.is_open() == true)

  vim.cmd('tabnew')
  check("not open in fresh tab 2 (independent per-tab state)", p.is_open() == false)

  p.open()
  check("open in tab 2 independently", p.is_open() == true)

  vim.cmd('tabclose')  -- back to tab 1
  check("still open in tab 1 after closing tab 2", p.is_open() == true)

  p.close()
end

-- ============================================================================
-- SECTION: buffer panel content correctness
-- ============================================================================

print("== bufpanel content ==")

do
  local ui = require('pkm.ui')

  -- Open two throwaway named buffers so bufpanel has real, non-empty content
  -- to list (unnamed scratch buffers are excluded by bufpanel_build_lines).
  local f1 = vim.fn.tempname() .. '.md'
  local f2 = vim.fn.tempname() .. '.md'
  vim.fn.writefile({ '# one' }, f1)
  vim.fn.writefile({ '# two' }, f2)
  vim.cmd('edit ' .. vim.fn.fnameescape(f1))
  vim.cmd('vsplit ' .. vim.fn.fnameescape(f2))

  ui._bufpanel.open()
  check("bufpanel opens", ui._bufpanel.is_open())

  local win = ui._bufpanel.get_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local found_f1, found_f2 = false, false
  for _, line in ipairs(lines) do
    if line:find(vim.fn.fnamemodify(f1, ':t'), 1, true) then found_f1 = true end
    if line:find(vim.fn.fnamemodify(f2, ':t'), 1, true) then found_f2 = true end
  end
  check("bufpanel lists both open files", found_f1 and found_f2)

  check("bufpanel buffer is not modifiable (read-only listing)",
    vim.api.nvim_get_option_value('modifiable', { buf = buf }) == false)

  ui._bufpanel.close()
  check("bufpanel closes", not ui._bufpanel.is_open())

  vim.cmd('bwipeout! ' .. vim.fn.bufnr(f1))
  vim.cmd('bwipeout! ' .. vim.fn.bufnr(f2))
  vim.fn.delete(f1)
  vim.fn.delete(f2)
end

print(string.format("\n%s", failures == 0 and "ALL PASS" or (failures .. " FAILURE(S)")))
if failures > 0 then vim.cmd("cquit 1") end
