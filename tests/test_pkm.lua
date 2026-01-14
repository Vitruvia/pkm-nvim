-- test_pkm.lua
-- Minimal test configuration for PKM system
-- Run this before adding to your main init.lua
-- Usage: nvim -u test_pkm.lua

-- Disable all plugins except PKM
vim.opt.runtimepath:prepend(vim.fn.stdpath('config'))

-- Basic settings
vim.opt.number = true
vim.opt.wrap = true
vim.g.mapleader = ' '

-- Colors
vim.cmd('colorscheme default')

print("=" .. string.rep("=", 60))
print("PKM System - Test Configuration")
print("=" .. string.rep("=", 60))
print("")

-- Detect OS and set appropriate path
local pkm_root
if vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
  pkm_root = "P:/Notes"
  print("Detected: Windows")
else
  pkm_root = "/mnt/p/Notes"
  print("Detected: Linux/WSL/Unix")
end

print("Root path: " .. pkm_root)
print("")

-- Test 1: Check if PKM module exists
print("Test 1: Loading PKM module...")
local ok, pkm = pcall(require, 'pkm')
if not ok then
  print("❌ FAIL: Could not load PKM module")
  print("   Error: " .. tostring(pkm))
  print("")
  print("   Check that files are in: " .. vim.fn.stdpath('config') .. "/lua/pkm/")
  return
end
print("✅ PASS: PKM module loaded")
print("")

-- Test 2: Check if setup function exists
print("Test 2: Checking setup function...")
if type(pkm.setup) ~= "function" then
  print("❌ FAIL: setup function not found")
  return
end
print("✅ PASS: setup function exists")
print("")

-- Test 3: Run setup
print("Test 3: Running setup...")
local setup_ok, setup_err = pcall(function()
  pkm.setup({
    root_path = pkm_root,
    
    keymaps = {
      -- Note creation
      new_note = "<leader>nn",
      new_journal = "<leader>nj",
      new_scratchpad = "<leader>ns",
      quick_capture = "<leader>nq",
      convert_note = "<leader>nx",
      
      -- Citations
      insert_citation = "<leader>nc",
      goto_citation = "<leader>ng",
      preview_citation = "K",
      
      -- Navigation
      link_note = "<leader>nl",
      follow_link = "gf",
      backlinks = "<leader>nb",
      
      -- Search
      search = "<leader>nf",
      browse_tags = "<leader>nt",
      recent_journals = "<leader>nr",
    },
  })
end)

if not setup_ok then
  print("❌ FAIL: Setup failed")
  print("   Error: " .. tostring(setup_err))
  return
end
print("✅ PASS: Setup completed")
print("")

-- Test 4: Check commands
print("Test 4: Checking commands...")
local commands = {
  'PKMNewNote',
  'PKMNewJournal',
  'PKMNewScratchpad',
  'PKMQuickCapture',
  'PKMConvertNote',
  'PKMInsertCitation',
  'PKMStats',
  'PKMSearch',
}

local all_commands_ok = true
for _, cmd in ipairs(commands) do
  local cmd_exists = vim.fn.exists(':' .. cmd) == 2
  if cmd_exists then
    print("  ✓ " .. cmd)
  else
    print("  ✗ " .. cmd)
    all_commands_ok = false
  end
end

if all_commands_ok then
  print("✅ PASS: All commands registered")
else
  print("❌ FAIL: Some commands missing")
  return
end
print("")

-- Test 5: Test basic functionality
print("Test 5: Testing basic functionality...")

-- Test timestamp
local ts_ok, ts = pcall(function()
  return pkm.timestamp.now(true, true)
end)

if ts_ok and ts.year then
  print("  ✓ Timestamp: " .. pkm.timestamp.to_human(ts))
else
  print("  ✗ Timestamp failed")
  all_commands_ok = false
end

-- Test YAML
local yaml_ok, yaml_result = pcall(function()
  local test_data = {title = "Test", tags = {"test1", "test2"}}
  return pkm.yaml.generate_yaml(test_data)
end)

if yaml_ok and #yaml_result > 0 then
  print("  ✓ YAML generation")
else
  print("  ✗ YAML generation failed")
  all_commands_ok = false
end

-- Test path handling
local path_sep = package.config:sub(1, 1)
if vim.fn.has('win32') == 1 then
  if path_sep == "\\" then
    print("  ✓ Path separator: \\ (Windows)")
  else
    print("  ⚠ Path separator unexpected: " .. path_sep)
  end
else
  if path_sep == "/" then
    print("  ✓ Path separator: / (Unix)")
  else
    print("  ⚠ Path separator unexpected: " .. path_sep)
  end
end

if all_commands_ok then
  print("✅ PASS: Basic functionality working")
else
  print("❌ FAIL: Some functionality issues")
end
print("")

-- Summary
print("=" .. string.rep("=", 60))
print("Test Summary")
print("=" .. string.rep("=", 60))
print("")

if all_commands_ok then
  print("🎉 All tests passed!")
  print("")
  print("Next steps:")
  print("1. Try: :PKMQuickCapture")
  print("2. Try: :PKMNewNote")
  print("3. Try: :PKMStats")
  print("")
  print("If everything works, add PKM setup to your main init.lua")
  print("See Integration Guide for detailed instructions")
else
  print("⚠️  Some tests failed")
  print("")
  print("Troubleshooting:")
  print("1. Check file locations: " .. vim.fn.stdpath('config') .. "/lua/pkm/")
  print("2. Verify all 7 PKM files exist (init, yaml, timestamp, citations, notes, journal, ui)")
  print("3. Check for syntax errors: :messages")
  print("4. Review Integration Guide")
end
print("")

-- Create helpful commands for testing
vim.api.nvim_create_user_command('TestPKM', function()
  print("Running PKM tests...")
  vim.cmd('source ' .. vim.fn.expand('<script>'))
end, {})

vim.api.nvim_create_user_command('PKMInfo', function()
  print("PKM System Information")
  print("=====================")
  print("")
  print("Root path: " .. pkm_root)
  print("Config path: " .. vim.fn.stdpath('config'))
  print("PKM path: " .. vim.fn.stdpath('config') .. "/lua/pkm/")
  print("OS: " .. (vim.fn.has('win32') == 1 and "Windows" or "Unix"))
  print("Path separator: " .. package.config:sub(1, 1))
  print("")
  print("Modules:")
  for _, mod in ipairs({'init', 'yaml', 'timestamp', 'citations', 'notes', 'journal', 'ui'}) do
    local mod_ok = pcall(require, 'pkm.' .. mod)
    print("  " .. (mod_ok and "✓" or "✗") .. " pkm." .. mod)
  end
  print("")
  print("Commands available: " .. #commands)
  print("")
  print("Try: :PKMQuickCapture")
end, {})

print("Additional commands available:")
print("  :TestPKM   - Re-run tests")
print("  :PKMInfo   - Show PKM information")
print("")

--[[
USAGE:

Method 1 - Load in current Neovim session:
  :luafile test_pkm.lua

Method 2 - Start Neovim with this config:
  nvim -u test_pkm.lua

Method 3 - Test specific commands:
  :luafile test_pkm.lua
  :PKMQuickCapture
  :PKMStats
  :PKMInfo

EXPECTED OUTPUT:

All 5 tests should pass:
  ✅ Test 1: PKM module loaded
  ✅ Test 2: setup function exists
  ✅ Test 3: Setup completed
  ✅ Test 4: All commands registered
  ✅ Test 5: Basic functionality working

If any test fails:
  1. Check the error message
  2. Verify file locations
  3. Check Integration Guide
  4. Review file syntax

QUICK VERIFICATION:

After running this file:
  :PKMInfo              # Show PKM system info
  :PKMQuickCapture      # Test quick capture
  :PKMStats             # Should show statistics (even if 0)

If these work, your installation is correct!
]]
