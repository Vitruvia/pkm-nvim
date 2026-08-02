-- test/test_v1360_p1.lua
-- syntax.alpha_list_pattern — the matchadd pattern that highlights lettered list
-- markers (legal *alíneas*: a), b), aa) …). Tree-sitter emits no list node for
-- lowercase-letter markers, so they are highlighted via matchadd, mirroring the
-- roman markers (v1.35.0). Deliberately the ')' form only: the '.' form collides
-- with two-letter abbreviations (vs., cf., …) that can begin a line. This test
-- pins the pattern; the visual highlight rides the real-config smoke.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1360_p1.lua" -c "qa!"

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

check("alpha_list_pattern is exposed",
  type(syntax.alpha_list_pattern) == 'string' and #syntax.alpha_list_pattern > 0,
  vim.inspect(syntax.alpha_list_pattern))

local pat = syntax.alpha_list_pattern

-- Force 'ignorecase' on (matchadd honours it; the real config sets it): assert
-- the `\C` in the pattern keeps an uppercase `A)` from being painted as an alínea.
vim.o.ignorecase = true

-- { input line, expected matched marker ('' = must not match) }
local cases = {
  { 'a) primeira alínea',   'a)'  },
  { 'b) segunda',           'b)'  },
  { 'aa) past z',           'aa)' },
  { '    c) indented',      'c)'  },   -- leading indentation allowed
  { '> a) inside a quote',  'a)'  },   -- blockquote prefix allowed
  { 'a)',                   'a)'  },   -- empty item at end of line
  { 'a. dot form',          ''    },   -- '.' form intentionally not matched
  { 'I) roman paren',       ''    },   -- uppercase → roman family, not alpha
  { '1) arabic paren',      ''    },   -- digit
  { 'options a) or b)',     ''    },   -- inline enumeration mid-line, not line-start
  { 'the cat sat',          ''    },   -- plain prose
  { 'A) uppercase',         ''    },   -- uppercase must NOT fold-match as an alínea
  { 'C) uppercase',         ''    },   -- (C is roman-ish, but this is the alpha pattern)
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
