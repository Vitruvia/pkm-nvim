-- test/min_init.lua
-- Minimal, isolated init for headless PKM.nvim testing.
--
-- Deliberately does NOT load the user's real Neovim config, init.lua, or
-- Lazy-managed plugin copy — points runtimepath directly at THIS repo's
-- own lua/ directory, resolved from this file's own location, so it works
-- regardless of the shell's current working directory and always exercises
-- the local working tree about to be committed, not whatever is currently
-- installed via Lazy.
--
-- Usage (from repo root, or anywhere — CWD no longer matters for rtp):
--   nvim --headless -u test/min_init.lua -c "luafile test/test_<phase>.lua" -c "qa!"

local this_file = debug.getinfo(1, "S").source:sub(2)   -- strip leading '@'
local repo_root = vim.fn.fnamemodify(this_file, ':p:h:h')  -- test/min_init.lua -> repo root

vim.opt.runtimepath:prepend(repo_root)

-- Disposable test run: never read or write the user's real ShaDa file
-- (marks, registers, command/search history, oldfiles). Equivalent to
-- passing -i NONE on the command line, set here so it applies automatically
-- without editing the invocation. Also sidesteps E138 (all ShaDa temp-file
-- suffixes exhausted) from repeated rapid headless invocations never
-- completing their atomic write+rename.
vim.o.shadafile = 'NONE'

-- Disposable scratch corpus — never the real Notes tree, per the Standing
-- Verification Protocol. Fresh temp directory every run.
local scratch_root = vim.fn.tempname()
vim.fn.mkdir(scratch_root, 'p')

require('pkm').setup({
  root_path = scratch_root,
})
