-- test_yaml_fix.lua
-- Comprehensive test suite for YAML generation fixes
-- Run with: nvim -u NONE -c "luafile test_yaml_fix.lua"

-- ============================================================================
-- VALIDATION CHECKLIST
-- ============================================================================
--[[
PRE-FIX CHECKLIST:
☐ Backup current yaml.lua
☐ Document current behavior
☐ Create isolated test environment

YAML GENERATION REQUIREMENTS:
☐ Empty arrays must generate as `[]`
☐ Empty nested objects must have proper indentation
☐ Non-empty arrays must generate with `-` items
☐ Mixed empty/non-empty must work
☐ Structure preserved through parse → generate → parse cycle
☐ No ambiguous output at any nesting level
☐ Proper indentation maintained recursively

CITATION INTEGRATION REQUIREMENTS:
☐ First citation works (baseline)
☐ Second citation works (critical failure point)
☐ Third+ citations work
☐ Multiple note citations work
☐ Multiple bib citations work
☐ Mixed note+bib citations work

DELETION REQUIREMENTS:
☐ Deleting one cited note preserves others
☐ Empty groups remain as `bib: []` and `notes: []`
☐ Structure stays intact after deletion
☐ No fields disappear

CLEANUP REQUIREMENTS:
☐ Cleanup doesn't create new corruption
☐ Cleanup preserves correct structure
☐ Update references works correctly

POST-FIX VERIFICATION:
☐ All unit tests pass
☐ All integration tests pass
☐ No regression in existing features
☐ 24+ hours of stable testing
☐ Edge cases verified
]]

-- ============================================================================
-- TEST FRAMEWORK
-- ============================================================================

local TEST_RESULTS = {
  passed = 0,
  failed = 0,
  total = 0,
  failures = {}
}

local function test_case(name, test_fn)
  TEST_RESULTS.total = TEST_RESULTS.total + 1
  
  local success, err = pcall(test_fn)
  
  if success then
    TEST_RESULTS.passed = TEST_RESULTS.passed + 1
    print(string.format("✓ PASS: %s", name))
  else
    TEST_RESULTS.failed = TEST_RESULTS.failed + 1
    table.insert(TEST_RESULTS.failures, {name = name, error = tostring(err)})
    print(string.format("✗ FAIL: %s", name))
    print(string.format("  Error: %s", tostring(err)))
  end
end

local function assert_equals(expected, actual, msg)
  if expected ~= actual then
    error(string.format("%s\nExpected: %s\nActual: %s", 
      msg or "Values not equal", tostring(expected), tostring(actual)))
  end
end

local function assert_match(pattern, str, msg)
  if not string.match(str, pattern) then
    error(string.format("%s\nPattern: %s\nString: %s", 
      msg or "Pattern not found", pattern, str))
  end
end

local function assert_not_match(pattern, str, msg)
  if string.match(str, pattern) then
    error(string.format("%s\nPattern: %s\nFound in: %s", 
      msg or "Pattern should not match", pattern, str))
  end
end

local function assert_table_structure(expected_structure, actual_table, msg)
  for key, expected_type in pairs(expected_structure) do
    local actual_type = type(actual_table[key])
    if actual_type ~= expected_type then
      error(string.format("%s\nKey '%s': expected type %s, got %s", 
        msg or "Table structure mismatch", key, expected_type, actual_type))
    end
  end
end

-- ============================================================================
-- UNIT TESTS: YAML GENERATION
-- ============================================================================

local function run_yaml_generation_tests()
  print("\n=== YAML Generation Unit Tests ===\n")
  
  -- Mock yaml module (replace with actual require after fix)
  local yaml = require('pkm.yaml')
  
  -- Test 1: Empty nested structure
  test_case("Empty nested structure generates correctly", function()
    local data = {
      title = "Test",
      cited_by = {
        bib = {},
        notes = {}
      }
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    -- Must have explicit empty array notation
    assert_match("bib: %[%]", result, "bib should be empty array")
    assert_match("notes: %[%]", result, "notes should be empty array")
    
    -- Must NOT have top-level bib or notes
    assert_not_match("^bib:", result, "bib should not be at top level")
    assert_not_match("^notes:", result, "notes should not be at top level")
    
    -- Verify indentation under cited_by
    assert_match("cited_by:\n  bib:", result, "bib should be indented under cited_by")
  end)
  
  -- Test 2: Mixed empty and non-empty
  test_case("Mixed empty and non-empty arrays", function()
    local data = {
      cites = {
        bib = {},
        notes = {
          {identifier = "note-0001", title = "Test"}
        }
      }
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    assert_match("bib: %[%]", result, "Empty bib should be explicit")
    assert_match("notes:\n%s+%-", result, "Non-empty notes should have items")
    assert_match("identifier: note%-0001", result, "Should have identifier")
  end)
  
  -- Test 3: Multiple levels of nesting
  test_case("Multiple nesting levels", function()
    local data = {
      level1 = {
        level2 = {
          level3 = {}
        }
      }
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    -- Verify proper indentation hierarchy
    assert_match("level1:\n  level2:\n    level3: %[%]", result, 
      "Multiple nesting levels should have correct indentation")
  end)
  
  -- Test 4: Round-trip preservation
  test_case("Round-trip parse → generate → parse", function()
    local original = {
      cited_by = {
        bib = {},
        notes = {{identifier = "note-0001"}}
      }
    }
    
    -- Generate YAML
    local yaml_lines = yaml.generate_yaml(original)
    
    -- Parse it back
    local reparsed = yaml.parse_yaml(yaml_lines)
    
    -- Verify structure preserved
    assert_table_structure({
      cited_by = "table"
    }, reparsed, "Top level structure")
    
    assert_table_structure({
      bib = "table",
      notes = "table"
    }, reparsed.cited_by, "Nested structure")
    
    assert_equals(0, #reparsed.cited_by.bib, "Empty array should be empty")
    assert_equals(1, #reparsed.cited_by.notes, "Non-empty array should have items")
  end)
  
  -- Test 5: Empty top-level array
  test_case("Empty top-level array", function()
    local data = {
      tags = {}
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    assert_match("tags: %[%]", result, "Empty top-level array should be explicit")
  end)
  
  -- Test 6: Complex nested structure
  test_case("Complex nested structure with multiple types", function()
    local data = {
      title = "Test Note",
      status = "draft",
      tags = {"tag1", "tag2"},
      cites = {
        bib = {
          {identifier = "bib-0005", title = "Book"}
        },
        notes = {}
      },
      cited_by = {
        bib = {},
        notes = {}
      }
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    -- Verify all components
    assert_match("title: Test Note", result)
    assert_match("tags:\n%s+%- tag1", result)
    assert_match("cites:\n%s+bib:\n%s+%- identifier:", result)
    assert_match("notes: %[%]", result)
    assert_match("cited_by:\n%s+bib: %[%]", result)
  end)
end

-- ============================================================================
-- INTEGRATION TESTS: CITATION SYSTEM
-- ============================================================================

local function run_citation_integration_tests()
  print("\n=== Citation Integration Tests ===\n")
  
  -- These tests require the full PKM system
  -- Run manually in Neovim after YAML fix
  
  print("Citation integration tests should be run manually:")
  print("1. Create three test notes")
  print("2. Add first citation - verify clean structure")
  print("3. Add second citation - verify no corruption")
  print("4. Add third citation - verify structure intact")
  print("5. Delete one citation - verify others preserved")
  print("6. Run cleanup - verify no new corruption")
end

-- ============================================================================
-- REGRESSION TESTS
-- ============================================================================

local function run_regression_tests()
  print("\n=== Regression Tests ===\n")
  
  local yaml = require('pkm.yaml')
  
  -- Test: Existing features still work
  test_case("Simple key-value pairs", function()
    local data = {
      title = "Test",
      author = "User",
      status = "draft"
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    assert_match("title: Test", result)
    assert_match("author: User", result)
    assert_match("status: draft", result)
  end)
  
  test_case("Non-empty arrays", function()
    local data = {
      tags = {"tag1", "tag2", "tag3"}
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    assert_match("tags:\n%s+%- tag1", result)
    assert_match("%- tag2", result)
    assert_match("%- tag3", result)
  end)
  
  test_case("Nested objects with content", function()
    local data = {
      metadata = {
        created = "2025-01-01",
        modified = "2025-01-02"
      }
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    assert_match("metadata:\n%s+created:", result)
    assert_match("modified: 2025%-01%-02", result)
  end)
end

-- ============================================================================
-- EDGE CASE TESTS
-- ============================================================================

local function run_edge_case_tests()
  print("\n=== Edge Case Tests ===\n")
  
  local yaml = require('pkm.yaml')
  
  test_case("Deeply nested empty structures", function()
    local data = {
      a = {
        b = {
          c = {
            d = {}
          }
        }
      }
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    -- Should have proper indentation at all levels
    assert_match("a:\n%s+b:\n%s+c:\n%s+d: %[%]", result)
  end)
  
  test_case("Mixed array and object children", function()
    local data = {
      parent = {
        array_child = {},
        object_child = {
          nested = "value"
        }
      }
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    assert_match("array_child: %[%]", result)
    assert_match("object_child:\n%s+nested: value", result)
  end)
  
  test_case("Empty table at different positions", function()
    local data = {
      before = "value",
      empty = {},
      after = "value"
    }
    
    local lines = yaml.generate_yaml(data)
    local result = table.concat(lines, "\n")
    
    assert_match("empty: %[%]", result)
  end)
end

-- ============================================================================
-- MAIN TEST RUNNER
-- ============================================================================

local function print_summary()
  print("\n" .. string.rep("=", 70))
  print("TEST SUMMARY")
  print(string.rep("=", 70))
  print(string.format("Total Tests: %d", TEST_RESULTS.total))
  print(string.format("Passed: %d ✓", TEST_RESULTS.passed))
  print(string.format("Failed: %d ✗", TEST_RESULTS.failed))
  print(string.rep("=", 70))
  
  if TEST_RESULTS.failed > 0 then
    print("\nFAILURES:")
    for _, failure in ipairs(TEST_RESULTS.failures) do
      print(string.format("\n✗ %s", failure.name))
      print(string.format("  %s", failure.error))
    end
    print("\n❌ YAML FIX NOT READY - DO NOT DEPLOY")
  else
    print("\n✅ ALL TESTS PASSED")
    print("✅ YAML FIX READY FOR INTEGRATION TESTING")
    print("\nNext steps:")
    print("1. Run citation integration tests manually")
    print("2. Test with real notes for 24 hours")
    print("3. Verify no regression")
    print("4. Update documentation")
  end
  
  print(string.rep("=", 70))
end

-- Run all test suites
print("PKM YAML Fix - Comprehensive Test Suite")
print("========================================\n")

run_yaml_generation_tests()
run_regression_tests()
run_edge_case_tests()
run_citation_integration_tests()

print_summary()

-- Return test results for programmatic use
return TEST_RESULTS
