-- Corrected test script for PKM system
-- Run with: nvim --headless -u NONE -c "luafile path/to/this/file.lua" -c "qa!"

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("✓ " .. name)
  else
    print("✗ " .. name .. ": " .. tostring(err))
  end
end

print("=== PKM System Tests ===\n")

-- Test 1: Check if PKM module loads
test("PKM module loads", function()
  local pkm = require('pkm')
  assert(pkm, "PKM module not found")
end)

-- Test 2: Check if submodules load
test("Submodules (citations, yaml) load", function()
  local citations = require('pkm.citations')
  assert(citations, "Citations module not found")
  local yaml = require('pkm.yaml')
  assert(yaml, "YAML module not found")
end)

-- ******************************************************
-- ** NEW AND IMPORTANT STEP: SETUP THE PLUGIN         **
-- ******************************************************
test("PKM plugin initializes via setup()", function()
  -- We must call setup() to register commands and autocmds
  require('pkm').setup({})
  print("  (PKM Setup Complete)")
end)
-- ******************************************************

-- Test 3: Check if commands exist AFTER setup
test("PKMSync command exists", function()
  assert(vim.fn.exists(':PKMSync') == 2, "PKMSync command not found")
end)

test("PKMValidate command exists", function()
  assert(vim.fn.exists(':PKMValidate') == 2, "PKMValidate command not found")
end)

test("PKMCleanupFrontmatter command exists", function()
  assert(vim.fn.exists(':PKMCleanupFrontmatter') == 2, "PKMCleanupFrontmatter command not found")
end)

test("PKMUpdateReferences command exists", function()
  assert(vim.fn.exists(':PKMUpdateReferences') == 2, "PKMUpdateReferences command not found")
end)

-- Test 4: Test YAML generation
test("YAML handles empty nested structures", function()
  local yaml = require('pkm.yaml')
  
  local data = {
    cites = { notes = {}, bib = {} },
    cited_by = { notes = {}, bib = {} }
  }
  
  local lines = yaml.generate_yaml(data)
  local result = table.concat(lines, "\n")
  
  assert(result:match("notes: %[%]"), "Empty notes array not properly formatted")
  assert(result:match("bib: %[%]"), "Empty bib array not properly formatted")
  
  local parsed = yaml.parse_yaml(lines)
  assert(type(parsed.cites.notes) == "table", "cites.notes should be table")
  assert(type(parsed.cites.bib) == "table", "cites.bib should be table")
end)

print("\n=== All Tests Complete ===")
