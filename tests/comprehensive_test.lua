-- comprehensive_test.lua
-- Tests all edge cases that could fail

package.path = package.path .. ';lua/?.lua'
local yaml = require('pkm.yaml')

local function test(name, fn)
  io.write(string.format("%-60s", name .. "..."))
  local ok, err = pcall(fn)
  if ok then
    print(" ✓")
    return true
  else
    print(" ✗")
    print("  Error: " .. tostring(err))
    return false
  end
end

local function assert_type(expected, actual, msg)
  if type(actual) ~= expected then
    error(string.format("%s: expected type %s, got %s", msg, expected, type(actual)))
  end
end

print("=== YAML Comprehensive Test Suite ===\n")

local passed = 0
local total = 0

-- Test 1: Simple empty nested structure
total = total + 1
if test("Test 1: Empty nested structure", function()
  local data = {cited_by = {bib = {}, notes = {}}}
  local lines = yaml.generate_yaml(data)
  local parsed = yaml.parse_yaml(lines)
  
  assert_type("table", parsed.cited_by, "cited_by")
  assert_type("table", parsed.cited_by.bib, "bib")
  assert_type("table", parsed.cited_by.notes, "notes")
end) then passed = passed + 1 end

-- Test 2: Mixed empty and non-empty
total = total + 1
if test("Test 2: Mixed empty and non-empty arrays", function()
  local data = {
    cites = {
      bib = {},
      notes = {{identifier = "note-0001", title = "Test"}}
    }
  }
  
  local lines = yaml.generate_yaml(data)
  
  -- Debug: show generated YAML
  print("\n  Generated YAML:")
  for i, line in ipairs(lines) do
    print(string.format("    [%d] %s", i, line))
  end
  
  local parsed = yaml.parse_yaml(lines)
  
  assert_type("table", parsed.cites, "cites")
  assert_type("table", parsed.cites.bib, "bib")
  assert_type("table", parsed.cites.notes, "notes")
  
  -- Check bib is empty
  if next(parsed.cites.bib) ~= nil then
    error("bib should be empty")
  end
  
  -- Check notes has content
  if #parsed.cites.notes ~= 1 then
    error("notes should have 1 item, has " .. #parsed.cites.notes)
  end
end) then passed = passed + 1 end

-- Test 3: Three levels of nesting
total = total + 1
if test("Test 3: Three levels of nesting", function()
  local data = {
    level1 = {
      level2 = {
        level3 = {}
      }
    }
  }
  
  local lines = yaml.generate_yaml(data)
  local parsed = yaml.parse_yaml(lines)
  
  assert_type("table", parsed.level1, "level1")
  assert_type("table", parsed.level1.level2, "level2")
  assert_type("table", parsed.level1.level2.level3, "level3")
end) then passed = passed + 1 end

-- Test 4: Multiple empty siblings
total = total + 1
if test("Test 4: Multiple empty siblings", function()
  local data = {
    group1 = {
      empty1 = {},
      empty2 = {},
      empty3 = {}
    }
  }
  
  local lines = yaml.generate_yaml(data)
  local parsed = yaml.parse_yaml(lines)
  
  assert_type("table", parsed.group1, "group1")
  assert_type("table", parsed.group1.empty1, "empty1")
  assert_type("table", parsed.group1.empty2, "empty2")
  assert_type("table", parsed.group1.empty3, "empty3")
end) then passed = passed + 1 end

-- Test 5: Empty at different positions
total = total + 1
if test("Test 5: Empty arrays at different positions", function()
  local data = {
    before = "value",
    empty1 = {},
    middle = "value",
    empty2 = {},
    after = "value"
  }
  
  local lines = yaml.generate_yaml(data)
  local parsed = yaml.parse_yaml(lines)
  
  assert_type("table", parsed.empty1, "empty1")
  assert_type("table", parsed.empty2, "empty2")
end) then passed = passed + 1 end

-- Test 6: Complex real-world structure
total = total + 1
if test("Test 6: Complex real-world structure", function()
  local data = {
    title = "Test Note",
    tags = {"tag1", "tag2"},
    cites = {
      bib = {{identifier = "bib-0005"}},
      notes = {}
    },
    cited_by = {
      bib = {},
      notes = {}
    }
  }
  
  local lines = yaml.generate_yaml(data)
  local parsed = yaml.parse_yaml(lines)
  
  assert_type("table", parsed.cites, "cites")
  assert_type("table", parsed.cites.bib, "cites.bib")
  assert_type("table", parsed.cites.notes, "cites.notes")
  assert_type("table", parsed.cited_by, "cited_by")
  assert_type("table", parsed.cited_by.bib, "cited_by.bib")
  assert_type("table", parsed.cited_by.notes, "cited_by.notes")
  
  -- Verify counts
  if #parsed.cites.bib ~= 1 then
    error("cites.bib should have 1 item")
  end
  if #parsed.cites.notes ~= 0 then
    error("cites.notes should be empty")
  end
end) then passed = passed + 1 end

-- Test 7: Top-level empty array
total = total + 1
if test("Test 7: Top-level empty array", function()
  local data = {tags = {}}
  local lines = yaml.generate_yaml(data)
  local parsed = yaml.parse_yaml(lines)
  
  assert_type("table", parsed.tags, "tags")
end) then passed = passed + 1 end

-- Test 8: Empty nested with non-empty parent
total = total + 1
if test("Test 8: Empty nested with non-empty parent", function()
  local data = {
    parent = {
      field = "value",
      nested = {
        empty = {}
      }
    }
  }
  
  local lines = yaml.generate_yaml(data)
  local parsed = yaml.parse_yaml(lines)
  
  assert_type("table", parsed.parent, "parent")
  assert_type("table", parsed.parent.nested, "nested")
  assert_type("table", parsed.parent.nested.empty, "empty")
end) then passed = passed + 1 end

-- Summary
print(string.rep("=", 70))
print(string.format("Results: %d/%d tests passed", passed, total))
if passed == total then
  print("✓ ALL TESTS PASSED - YAML fix is working correctly!")
else
  print(string.format("✗ %d test(s) failed", total - passed))
end
print(string.rep("=", 70))

return {passed = passed, total = total}
