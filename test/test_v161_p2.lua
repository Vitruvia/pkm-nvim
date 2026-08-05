-- =============================================================================
-- test_v161_p2 — index background build: CHUNKED completion on its own
-- =============================================================================
-- The feature: start_background_build() reads the corpus in idle slices
-- (bg_step, rescheduled via vim.defer_fn) and finishes without a single freeze,
-- yielding the same complete index a full scan would. Driven by vim.wait, which
-- pumps the event loop so the deferred slices run.
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
local N = 1200                       -- > BG_CHUNK (400): several slices
bench.gen_notes(N, dir)

ok('index cold at start', index.is_built() == false)

index.start_background_build()
ok('not built immediately (chunked, deferred)', index.is_built() == false)

-- Let the idle slices run to completion.
vim.wait(10000, function() return index.is_built() end, 10)
ok('background build finished on its own', index.is_built() == true)

local entries = index.get_all()
ok('all notes indexed by the chunked build (' .. #entries .. '/' .. N .. ')', #entries == N)

-- Idempotent when already built.
index.start_background_build()
ok('start_background_build no-ops when built', #index.get_all() == N)

print(fails == 0 and 'ALL PASS' or ('FAILURES: ' .. fails))
