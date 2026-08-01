-- test/test_v1230_p1.lua
-- pkm.api.find_all — cross-vault discovery, and its non-disruptive seam
-- index.scan_root. `find`/`query` read only the active vault's index, so they
-- cannot answer "which of my vaults holds X" (the gap the formal eval confirmed).
-- find_all sweeps every registered vault (plus the active root), reading each
-- non-active vault straight from its files without switching the active root or
-- rebuilding the live index. The decisive case: a term unique to the NON-active
-- vault — find misses it, find_all catches it.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1230_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

-- A vault in `find_all`'s result whose matches to inspect.
local function vault_named(res, name)
  for _, v in ipairs(res.vaults or {}) do if v.vault == name then return v end end
  return nil
end
local function has_tag(v, tag)
  for _, t in ipairs(v and v.tags or {}) do if t == tag then return true end end
  return false
end
local function note_titled(v, title)
  for _, n in ipairs(v and v.notes or {}) do if n.title == title then return true end end
  return false
end

local pkm   = require('pkm')
local base  = vim.fn.tempname()
local nvroot = base .. '/Note-Vault'
local alpha = nvroot .. '/00 - Alpha'
local beta  = nvroot .. '/01 - Beta'
for _, d in ipairs({ alpha .. '/03-Consolidated', beta .. '/03-Consolidated' }) do
  vim.fn.mkdir(d, 'p')
end

pkm.setup({ root_path = alpha, vaults_path = nvroot })

local vault = require('pkm.vault')
local index = require('pkm.index')
local api   = require('pkm.api')

-- Register both vaults.
local ok_save = vault.save({
  version = 1,
  vaults  = { { number = 0, name = 'Alpha' }, { number = 1, name = 'Beta' } },
})
assert(ok_save, 'registry save failed')

-- Alpha is the ACTIVE vault: create through the API (writes to the active root).
local a = api.create('note', { title = 'Alpha AFO note', by = 'claude', tags = { 'afo' },
  body = 'about administração financeira.' })
assert(a.ok, vim.inspect(a))

-- Beta is NOT active: write a fixture note straight to its folder. Its subject
-- (ringforge) exists in NO other vault — this is the term find cannot reach.
vim.fn.writefile({
  '---',
  'title: "Beta ringforge lore"',
  'tags:',
  '  - ringforge',
  '  - afo',
  '---',
  '',
  'worldbuilding notes.',
}, beta .. '/03-Consolidated/0001_note_beta-ringforge.md')

print("== index.scan_root reads another vault without touching the active index ==")
local before = #index.get_all()
local scanned = index.scan_root(beta)
check("scan_root returns Beta's note", #scanned == 1 and scanned[1].title == 'Beta ringforge lore',
  vim.inspect(scanned))
check("the active index is unchanged (Alpha only, same count)", #index.get_all() == before,
  string.format('before=%d after=%d', before, #index.get_all()))
check("the active note is still resolvable from the live index", api.get(a.path) ~= nil)

print("\n== the gap: a term unique to the NON-active vault ==")
local f_active = api.find('ringforge')          -- active vault only
check("api.find (active only) does NOT find ringforge", #f_active.notes == 0 and #f_active.tags == 0,
  vim.inspect(f_active))
local fa = api.find_all('ringforge')
check("api.find_all returns ok", fa.ok, vim.inspect(fa))
local beta_r = vault_named(fa, 'Beta')
check("find_all reaches Beta for ringforge", beta_r ~= nil, vim.inspect(fa))
check("Beta's ringforge tag is reported", has_tag(beta_r, 'ringforge'))
check("Beta's note is reported", note_titled(beta_r, 'Beta ringforge lore'))
check("Alpha does NOT appear for ringforge", vault_named(fa, 'Alpha') == nil, vim.inspect(fa))

print("\n== a shared term matches in BOTH vaults, grouped ==")
local both = api.find_all('afo')
local a_r, b_r = vault_named(both, 'Alpha'), vault_named(both, 'Beta')
check("Alpha appears for afo and is flagged active", a_r ~= nil and a_r.active == true, vim.inspect(a_r))
check("Beta appears for afo and is not flagged active", b_r ~= nil and b_r.active == nil, vim.inspect(b_r))
check("Alpha reports its afo tag", has_tag(a_r, 'afo'))
check("Beta reports its afo tag", has_tag(b_r, 'afo'))

print("\n== guards ==")
check("an empty term is refused", not api.find_all('').ok)
check("a term matching nothing yields an empty vault list",
  (function() local r = api.find_all('zzz-nonexistent'); return r.ok and #r.vaults == 0 end)())

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
