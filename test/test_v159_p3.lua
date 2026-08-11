-- test/test_v159_p3.lua
-- Pure-logic tests for v1.5.9 Phase 3: multi-line ((...)) meta-comment
-- detection. Exercises syntax.lua's find_meta_comments via
-- M._find_meta_comments (exposed for this test only; not part of the
-- module's public API — same pattern as notes.lua's M._is_same_file).
--
-- Run headless against a disposable scratch corpus:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v159_p3.lua" -c "qa!"

local syntax = require('pkm.syntax')

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

local function pos_eq(m, sr, sc, er, ec)
  return m.start_row == sr and m.start_col == sc
     and m.end_row == er and m.end_col == ec
end

print("== find_meta_comments ==")

do
  local got = syntax._find_meta_comments({ "some text ((a note)) more text" })
  check("single-line comment", #got == 1 and pos_eq(got[1], 0, 10, 0, 20))
end

do
  local got = syntax._find_meta_comments({
    "text before ((this comment",
    "continues here)) and text after",
  })
  check("two-line comment", #got == 1 and pos_eq(got[1], 0, 12, 1, 16))
end

do
  local got = syntax._find_meta_comments({
    "((start",
    "middle",
    "end))",
  })
  check("three-line comment ending at EOL", #got == 1 and pos_eq(got[1], 0, 0, 2, 5))
end

do
  local got = syntax._find_meta_comments({
    "((first))",
    "unrelated text",
    "((second))",
  })
  check("two separate single-line comments",
    #got == 2 and pos_eq(got[1], 0, 0, 0, 9) and pos_eq(got[2], 2, 0, 2, 10))
end

do
  local got = syntax._find_meta_comments({ "just plain text", "more plain text" })
  check("no comment present", #got == 0)
end

do
  local lines = { "((unmatched start" }
  for i = 1, 60 do lines[#lines + 1] = "filler line " .. i end
  lines[#lines + 1] = "))  -- unrelated closing far below"
  local got = syntax._find_meta_comments(lines)
  check("unmatched (( beyond MAX_META_COMMENT_LINES is suppressed", #got == 0)
end

do
  local lines = { "((short span" }
  for i = 1, 5 do lines[#lines + 1] = "filler " .. i end
  lines[#lines + 1] = "end))"
  local got = syntax._find_meta_comments(lines)
  check("within-cap multi-line comment still matches", #got == 1)
end

do
  local got = syntax._find_meta_comments({})
  check("empty buffer", #got == 0)
end

-- Item 3: a comment whose text ENDS in a parenthetical must keep its final ')'.
-- The old lazy `.-)` stopped at the first "))", losing the last ')'.
do
  local got = syntax._find_meta_comments({ "((a note (with an aside)))" })
  check("trailing parenthetical keeps final ')'",
    #got == 1 and pos_eq(got[1], 0, 0, 0, 26))
end

do
  -- The report's own case (single line): three closing parens, all inside.
  local line = "((the map lives in each study guide (probably as a level-2 heading)))"
  local got = syntax._find_meta_comments({ line })
  check("reported case: three trailing parens all covered",
    #got == 1 and pos_eq(got[1], 0, 0, 0, #line))
end

do
  local got = syntax._find_meta_comments({ "((mid (nested) tail))" })
  check("nested paren mid-comment", #got == 1 and pos_eq(got[1], 0, 0, 0, 21))
end

do
  -- Reported case spanning lines: the closing "))" rides a trailing "(…))".
  local got = syntax._find_meta_comments({
    "((the map lives in the study guide of each subject",
    "(probably as a level-2 heading))).",
  })
  check("multi-line comment with trailing parenthetical",
    #got == 1 and pos_eq(got[1], 0, 0, 1, 33))
end

do
  -- Unbalanced inner parens do NOT form a meta-comment (ends on a lone ')').
  local got = syntax._find_meta_comments({ "((a)b) plain" })
  check("unbalanced inner parens rejected", #got == 0)
end

print(string.format("\n%s", failures == 0 and "ALL PASS" or (failures .. " FAILURE(S)")))
if failures > 0 then vim.cmd("cquit 1") end
