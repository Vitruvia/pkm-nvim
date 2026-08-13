-- test/test_v1760_p1.lua
-- syntax._find_inciso_markers — the block-aware inciso scan that replaced the
-- per-line matchadd (G9, v1.76.0). An uppercase-alpha list (A -, B -, C - …)
-- contains roman-letter items (C, D, I, L, M, V, X); a stateless regex painted
-- exactly those and left A/B/E/… plain. The scan groups a list into a block and
-- paints it only when EVERY marker is a canonical roman numeral.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1760_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local syntax = require('pkm.syntax')

check("_find_inciso_markers is exposed",
  type(syntax._find_inciso_markers) == 'function',
  type(syntax._find_inciso_markers))

local find = syntax._find_inciso_markers

-- Helper: the set of 0-based rows the scan would paint, as a sorted list.
local function painted_rows(lines)
  local rows = {}
  for _, m in ipairs(find(lines)) do rows[#rows + 1] = m.row end
  table.sort(rows)
  return rows
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

print("\n== a genuine roman inciso block paints every marker ==")
check("I -, II -, III - → rows 0,1,2 painted",
  same(painted_rows({ 'I - um', 'II - dois', 'III - tres' }), { 0, 1, 2 }))

print("\n== an uppercase-alpha block paints NOTHING (the G9 fix) ==")
check("A -, B -, C -, D - → none painted (C,D would have been mis-coloured)",
  same(painted_rows({ 'A - alpha', 'B - beta', 'C - gamma', 'D - delta' }), {}))

print("\n== a lone marker is its own block ==")
check("standalone C - (valid roman) still paints",
  same(painted_rows({ 'texto', '', 'C - referencia', '', 'mais texto' }), { 2 }))
check("standalone A - (not roman) does not paint",
  same(painted_rows({ 'texto', '', 'A - item', '', 'mais texto' }), {}))

print("\n== a blank line separates blocks; a roman block after an alpha one survives ==")
check("alpha block then (blank) roman block → only the roman rows paint",
  same(painted_rows({
    'A - alpha', 'B - beta', 'C - gamma',   -- rows 0,1,2 : alpha → suppressed
    '',                                       -- row 3      : boundary
    'I - um', 'II - dois',                    -- rows 4,5   : roman → painted
  }), { 4, 5 }))

print("\n== a change of indent starts a new block ==")
check("outer roman + deeper alpha → only the outer roman paints",
  same(painted_rows({
    'I - um',                                 -- row 0 : roman, indent 0
    '    A - sub-a',                           -- row 1 : alpha, indent 4 → own block, suppressed
    '    B - sub-b',                           -- row 2 : alpha, indent 4
    'II - dois',                               -- row 3 : roman, indent 0 → new block, painted
  }), { 0, 3 }))

print("\n== a non-blank continuation line stays inside the block ==")
check("wrapped inciso text does not split the roman block",
  same(painted_rows({
    'I - primeiro inciso que',
    '  continua nesta linha sem marcador',    -- continuation, non-blank → not a boundary
    'II - segundo',
  }), { 0, 2 }))

print("\n== blockquote-prefixed incisos are recognised ==")
check("> I - / > II - paint",
  same(painted_rows({ '> I - citado', '> II - citado' }), { 0, 1 }))

print("\n== hyphenation and the dropped '.'/')' forms are not markers ==")
check("I-word, I. dot, I) paren → none painted",
  same(painted_rows({ 'I-word', 'I. dot', 'I) paren' }), {}))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
