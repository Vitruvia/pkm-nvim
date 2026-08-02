-- test/test_v1420_p1.lua
-- syntax.enable(bufnr, highlight_only) — the extraction seam. highlight_only=true
-- applies the pure highlighting (tree-sitter, matchadd/extmark markers) WITHOUT the
-- PKM-note behaviour (frontmatter fold, window options, zE remap); the default
-- (full) still creates the fold. This is what lets the highlighter run on arbitrary
-- markdown and be pulled out as a standalone plugin. Also checks the config flag.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1420_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })
local syntax = require('pkm.syntax')
local SUB_NS = vim.api.nvim_create_namespace('pkm_subalinea')

local frontmatter = { '---', 'title: x', '---', '', 'i. subalínea um', 'ii. subalínea dois' }

local function fresh_buf()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, frontmatter)
  return buf
end

print("== highlight_only=true: pure highlighting, NO frontmatter fold ==")
local b1 = fresh_buf()
syntax.enable(b1, true)
vim.wait(400, function() return false end)
check("subalínea extmarks placed (pure highlight active)",
  #vim.api.nvim_buf_get_extmarks(b1, SUB_NS, 0, -1, {}) == 2)
check("no frontmatter fold created (note behaviour skipped)",
  vim.fn.foldlevel(1) == 0, 'foldlevel(1)=' .. vim.fn.foldlevel(1))

print("== full enable (default): the frontmatter fold IS created ==")
local b2 = fresh_buf()
syntax.enable(b2)
vim.wait(400, function() return false end)
check("subalínea extmarks placed here too",
  #vim.api.nvim_buf_get_extmarks(b2, SUB_NS, 0, -1, {}) == 2)
check("frontmatter fold created (foldlevel(1) >= 1)",
  vim.fn.foldlevel(1) >= 1, 'foldlevel(1)=' .. vim.fn.foldlevel(1))

print("== the config flag defaults to off ==")
local cfg = require('pkm').config
check("syntax.highlight_all_markdown defaults false",
  cfg.pkm_mode and cfg.pkm_mode.syntax and cfg.pkm_mode.syntax.highlight_all_markdown == false,
  vim.inspect(cfg.pkm_mode and cfg.pkm_mode.syntax))

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
