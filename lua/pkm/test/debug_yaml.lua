-- debug_yaml.lua
-- Run with: nvim -u NONE -c "luafile debug_yaml.lua"

-- Add your PKM path
package.path = package.path .. ';lua/?.lua'

-- Load yaml module
local yaml = require('pkm.yaml')

print("=== YAML Parser Debug Test ===\n")

-- Test data
local data = {
  cited_by = {
    bib = {},
    notes = {}
  }
}

print("1. ORIGINAL DATA:")
print("  cited_by:", type(data.cited_by))
print("  cited_by.bib:", type(data.cited_by.bib))
print("  cited_by.notes:", type(data.cited_by.notes))
print("")

-- Generate YAML
print("2. GENERATING YAML:")
local lines = yaml.generate_yaml(data)
for i, line in ipairs(lines) do
  -- Show with visible spaces
  local display = line:gsub(" ", "·")
  print(string.format("  [%2d] %s", i, display))
end
print("")

-- Show raw for verification
print("3. RAW YAML OUTPUT:")
for i, line in ipairs(lines) do
  print(string.format('  lines[%d] = "%s"', i, line))
end
print("")

-- Parse it back
print("4. PARSING BACK:")
local parsed = yaml.parse_yaml(lines)

print("  parsed:", type(parsed))
print("  parsed.cited_by:", type(parsed.cited_by))

if parsed.cited_by then
  print("  parsed.cited_by.bib:", type(parsed.cited_by.bib))
  print("  parsed.cited_by.notes:", type(parsed.cited_by.notes))
  
  -- Show actual values
  print("\n5. ACTUAL VALUES:")
  print("  cited_by = {")
  for k, v in pairs(parsed.cited_by) do
    print(string.format("    %s = %s (type: %s)", k, tostring(v), type(v)))
  end
  print("  }")
else
  print("  ERROR: cited_by is nil!")
end

-- Expected vs Actual
print("\n6. VALIDATION:")
local function check(name, expected, actual)
  if expected == actual then
    print(string.format("  ✓ %s: %s", name, expected))
    return true
  else
    print(string.format("  ✗ %s: expected %s, got %s", name, expected, actual))
    return false
  end
end

local all_pass = true
all_pass = check("cited_by type", "table", type(parsed.cited_by)) and all_pass
if parsed.cited_by then
  all_pass = check("bib type", "table", type(parsed.cited_by.bib)) and all_pass
  all_pass = check("notes type", "table", type(parsed.cited_by.notes)) and all_pass
end

print(string.format("\n%s", all_pass and "✓ ALL CHECKS PASSED" or "✗ SOME CHECKS FAILED"))
