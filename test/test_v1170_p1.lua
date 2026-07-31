-- test/test_v1170_p1.lua
-- The PKMCitation highlight pattern fix (a standing Known Bug: the matchadd
-- regex never matched a real citation — `\w` in a Vim `\v` collection excludes
-- digits and `\>` was a literal `>`). Asserts the exposed pattern matches valid
-- citation tokens and rejects what it must not: the digit-id case is exactly the
-- one the old collection dropped, and `note{...}` is the inert cross-vault form.
--
-- Run: nvim --headless -u test/min_init.lua -c "luafile test/test_v1170_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pat = require('pkm.syntax').citation_pattern
check("the pattern is exposed", type(pat) == 'string' and pat ~= '', tostring(pat))

local function m(s) return vim.fn.match(s, pat) >= 0 end

print("== valid citations match ==")
check("note[0042] — the digit id the old bug dropped", m('note[0042]'))
check("bib[abc]", m('bib[abc]'))
check("journal[0001]", m('journal[0001]'))
check("scratch[x_1-2]", m('scratch[x_1-2]'))
check("matches inside the outer [ ] wrapper", m('[note[0042]]'))
check("matches mid-line", m('see [note[0042]] here'))

print("\n== invalid shapes are rejected ==")
check("nota[0042] (wrong word)", not m('nota[0042]'))
check("note{0042} (inert cross-vault form)", not m('note{0042}'))
check("note[] (empty id)", not m('note[]'))
check("xnote[0042] (no word boundary)", not m('xnote[0042]'))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
