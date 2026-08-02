-- test/test_v1350_p1.lua
-- syntax.roman_list_pattern — the matchadd pattern that highlights roman-numeral
-- list markers (legal *incisos*: I., II., VII) …). Tree-sitter emits no list node
-- for uppercase-roman markers, so they are highlighted via matchadd instead of the
-- .scm node captures. This test asserts the exposed pattern matches the intended
-- markers (including behind blockquote/indent prefixes) and rejects near-misses.
-- Highlighting itself is per-window visual state the headless suite cannot see —
-- that rides the real-config smoke; here we pin the pattern.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1350_p1.lua" -c "qa!"

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

check("roman_list_pattern is exposed",
  type(syntax.roman_list_pattern) == 'string' and #syntax.roman_list_pattern > 0,
  vim.inspect(syntax.roman_list_pattern))

local pat = syntax.roman_list_pattern

-- { input line, expected matched marker ('' = must not match) }
local cases = {
  { 'I. primeiro inciso',     'I.'   },
  { 'II. segundo',            'II.'  },
  { 'III. terceiro',          'III.' },
  { 'VII) parenthesis form',  'VII)' },
  { '    IV. indented',       'IV.'  },   -- leading indentation allowed
  { '> I. inside a quote',    'I.'   },   -- blockquote prefix allowed
  { 'I.',                     'I.'   },   -- empty item at end of line
  { 'X)',                     'X)'   },
  { 'I.e. an abbreviation',   ''     },   -- no space after the dot → not a marker
  { '1. arabic list',         ''     },   -- arabic is a tree-sitter marker, not ours
  { 'a) lowercase alinea',    ''     },   -- lowercase letters are not roman
  { 'Investigate. the case',  ''     },   -- word beginning with I, not roman-only
  { 'Hello world',            ''     },   -- plain prose
}

for _, c in ipairs(cases) do
  local got = vim.fn.matchstr(c[1], pat)
  check(string.format('"%s" -> "%s"', c[1], c[2]), got == c[2],
    'got "' .. got .. '"')
end

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
