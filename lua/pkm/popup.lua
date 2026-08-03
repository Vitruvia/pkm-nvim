-- =============================================================================
-- pkm.popup — the cyclable pop-up container (Area 3 Phase 3.5b)
-- =============================================================================
-- Dependencies : pkm.telescope / pkm.ui / pkm.views / pkm.nav (all lazy)
-- Consumed by  : keymaps (nav_search)
--
-- The pop-up mirror of the sidebar: one pop-up that shows one content PROVIDER
-- at a time — `browse` (all notes), `views` (view names), `nav` (the focused
-- note's headings) — and cycles between them with <C-l> (Telescope only; the
-- vim.ui.select fallback cannot host a cycle). STANDALONE semantics: choosing an
-- entry does the provider-native action (open note / activate view / jump to
-- heading) and NEVER drives the sidebar. (The sidebar's own `/` is the separate,
-- sidebar-driving search — the two are different surfaces by design.)
--
-- Public API:
--   open(provider?) → open the pop-up on 'browse' | 'views' | 'nav'
--                     (default 'browse'); <C-l> cycles to the next.
-- =============================================================================

local M = {}

local ORDER = { 'browse', 'views', 'nav' }

--- The provider after `from` in the cycle order.
---@param from string
---@return string
local function next_provider(from)
  for i, p in ipairs(ORDER) do
    if p == from then return ORDER[(i % #ORDER) + 1] end
  end
  return ORDER[1]
end

M._next_provider = next_provider   -- exposed for tests

--- Open the cyclable pop-up on `provider`. <C-l> re-opens on the next provider.
---@param provider string|nil  'browse' | 'views' | 'nav' (default 'browse')
function M.open(provider)
  if not vim.tbl_contains(ORDER, provider) then provider = 'browse' end
  local opts     = { on_cycle = function() M.open(next_provider(provider)) end }
  local has_tele = pcall(require, 'telescope')

  if provider == 'browse' then
    if has_tele then require('pkm.telescope').browse(nil, opts)
    else             require('pkm.ui').browse() end
  elseif provider == 'views' then
    require('pkm.views').popup_search(opts)
  else -- 'nav'
    require('pkm.nav').search(opts)
  end
end

return M
