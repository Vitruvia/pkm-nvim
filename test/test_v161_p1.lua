-- =============================================================================
-- test_v161_p1 — index background build: SYNCHRONOUS COMPLETION mid-build
-- =============================================================================
-- The safety property: a caller that needs the index before the chunked
-- background build has finished must receive a COMPLETE index (bg_finish_sync),
-- never a partial one. Deterministic — no slice runs before get_all() here.
-- =============================================================================
local index = require('pkm.index')
local bench = require('pkm.bench')
local utils = require('pkm.utils')

local fails = 0
local function ok(label, cond)
  if not cond then fails = fails + 1 end
  print((cond and 'ok   ' or 'FAIL ') .. label)
end

local cfg = require('pkm').config
local dir = utils.join(cfg.root_path, cfg.folders.consolidated)
local N = 1200                       -- > BG_CHUNK (400): one slice cannot finish it
bench.gen_notes(N, dir)

-- setup()'s auto-warm is a 200ms defer that has not fired yet → we are cold.
ok('index cold at start', index.is_built() == false)

index.start_background_build()       -- queue gathered, active; no slice has run
ok('background build active, not yet built', index.is_built() == false)

-- Need the index NOW, before any chunked slice runs: must complete synchronously.
local entries = index.get_all()
ok('get_all mid-build returns COMPLETE index (' .. #entries .. '/' .. N .. ')', #entries == N)
ok('index reports built after sync completion', index.is_built() == true)

print(fails == 0 and 'ALL PASS' or ('FAILURES: ' .. fails))
