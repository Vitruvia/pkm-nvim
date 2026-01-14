local yaml = require('pkm.yaml')

-- Test 1: New note should have grouped structure
local template_data = require('pkm').config.frontmatter_templates.consolidated
print("Template cites structure:")
print("  cites:", vim.inspect(template_data.cites))
print("  Expected: {notes = {}, bib = {}}")

-- Test 2: Empty cites should maintain structure
local test_data = {cites = {notes = {}, bib = {}}}
local lines = yaml.generate_yaml(test_data)
print("\nGenerated empty cites:")
for _, line in ipairs(lines) do
  print("  " .. line)
end
print("  Should show: cites:\\n  notes: []\\n  bib: []")

-- Test 3: Parse should preserve structure
local parsed = yaml.parse_yaml(lines)
print("\nParsed structure:")
print("  cites.notes:", type(parsed.cites.notes))
print("  cites.bib:", type(parsed.cites.bib))
print("  Both should be: table")

local ok = type(parsed.cites) == "table" and
           type(parsed.cites.notes) == "table" and
           type(parsed.cites.bib) == "table"

print("\n" .. (ok and "✓ STRUCTURE TEST PASSED" or "✗ STRUCTURE TEST FAILED"))
