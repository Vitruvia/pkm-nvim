-- test/test_v1350_p1.lua
-- syntax.inciso_list_pattern — the matchadd pattern that highlights legal *inciso*
-- markers (LC 95/1998: uppercase roman + ' - ': I -, II -, III -). Tree-sitter emits
-- no list node for these, so they are highlighted via matchadd. Introduced in
-- v1.35.0 for the roman '.'/')' form; **retargeted in v1.37.0** to the ' - ' form
-- (the '.'/')' roman form was dropped). This test pins the pattern; the visual
-- highlight rides the real-config smoke.
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

check("inciso_list_pattern is exposed",
  type(syntax.inciso_list_pattern) == 'string' and #syntax.inciso_list_pattern > 0,
  vim.inspect(syntax.inciso_list_pattern))

local pat = syntax.inciso_list_pattern

-- Force 'ignorecase' on: matchadd honours it, and the author's real config sets
-- it. Without `\C` in the pattern, [IVXLCDM] would fold to also match lowercase
-- roman letters and highlight ordinary words (civil -). Assert it here.
vim.o.ignorecase = true

-- { input line, expected matched marker ('' = must not match) }
local cases = {
  { 'I - primeiro inciso',   'I -'   },
  { 'II - segundo',          'II -'  },
  { 'III - terceiro',        'III -' },
  { '    IV - indented',     'IV -'  },   -- leading indentation allowed
  { '> I - inside a quote',  'I -'   },   -- blockquote prefix allowed
  { 'I -',                   'I -'   },   -- empty item at end of line
  { 'I. dot form',           ''      },   -- the dropped '.'/')' roman form
  { 'I) paren form',         ''      },   -- likewise dropped
  { 'I-word',                ''      },   -- hyphenation, not ' - '
  { '1 - arabic',            ''      },   -- digit, not roman
  { 'a - lowercase',         ''      },   -- lowercase letter
  { 'civil - word',          ''      },   -- lowercase roman letters, must NOT fold-match
  { 'i - lowercase roman',   ''      },   -- lowercase i, must NOT fold-match
  { 'A - not roman',         ''      },   -- A is not a roman letter
  { 'Hello world',           ''      },   -- plain prose
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
