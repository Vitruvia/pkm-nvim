-- test/test_v1614_p1.lua
-- Browse-picker note-type filter — the live browse picker (telescope.live_picker,
-- backing :PKMBrowse / <leader>ff, the view note lists, and the pop-up's browse)
-- gained a <C-t> note-type cycle: all → note → agg → bib → journal → scratch, the
-- way to reach journal / scratchpad notes without the sidebar. The <C-t> key and
-- the in-picker reopen are Telescope-only (smoke); the pure pieces — the cycle
-- and the per-type predicate that filters the results — are asserted here.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1614_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local tele = require('pkm.telescope')

print("== the type cycle mirrors the sidebar (all → note → agg → bib → journal → scratch) ==")
check("_type_cycle is exposed", type(tele._type_cycle) == 'table', vim.inspect(tele._type_cycle))
local expected = { false, 'note', 'agg', 'bib', 'journal', 'scratch' }
check("cycle length is 6 (all + five types)", #tele._type_cycle == #expected,
  tostring(#tele._type_cycle))
check("cycle contents match (index 1 = false = all)", (function()
  for i = 1, #expected do if tele._type_cycle[i] ~= expected[i] then return false end end
  return true
end)(), vim.inspect(tele._type_cycle))
check("the <C-t> index math wraps 6 → 1", (6 % #tele._type_cycle) + 1 == 1)

print("\n== _passes_type: index 1 is 'all', the rest isolate one note type ==")
check("idx 1 (all) passes a note",    tele._passes_type('note', 1) == true)
check("idx 1 (all) passes a scratch", tele._passes_type('scratch', 1) == true)
check("idx 1 (all) passes nil-type",  tele._passes_type(nil, 1) == true)
check("nil type_idx defaults to 'all'", tele._passes_type('scratch', nil) == true)

check("idx 6 passes scratch",         tele._passes_type('scratch', 6) == true)
check("idx 6 REJECTS note",           tele._passes_type('note', 6) == false)
check("idx 6 REJECTS journal",        tele._passes_type('journal', 6) == false)

check("idx 5 passes journal",         tele._passes_type('journal', 5) == true)
check("idx 5 REJECTS scratch",        tele._passes_type('scratch', 5) == false)

check("idx 2 passes note",            tele._passes_type('note', 2) == true)
check("idx 2 REJECTS agg",            tele._passes_type('agg', 2) == false)

print("\n== every listed type is reachable through the cycle exactly once ==")
check("each of note/agg/bib/journal/scratch has one exclusive index", (function()
  local want = { note = false, agg = false, bib = false, journal = false, scratch = false }
  for idx = 2, #tele._type_cycle do
    local ty = tele._type_cycle[idx]
    if want[ty] ~= false then return false end   -- unknown or duplicate
    if not tele._passes_type(ty, idx) then return false end
    want[ty] = true
  end
  for _, seen in pairs(want) do if not seen then return false end end
  return true
end)())

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
