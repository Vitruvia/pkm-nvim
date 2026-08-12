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

-- The last pop-up search worth returning to: { provider, query }. Set only when a
-- pop-up search is COMMITTED (an entry is chosen with something typed), never by a
-- fresh open — so opening the pop-up clean and then pressing resume brings back the
-- earlier search rather than the empty panel that fresh open would otherwise leave
-- as Telescope's "last picker". This is what makes resume pop-up-specific.
local _last = nil

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

--- Launch the pop-up on `provider`, optionally seeding the prompt with `seed`.
--- `record` remembers a committed search (provider + typed query) as `_last` for
--- M.resume; `on_cycle` moves to the next provider (fresh, no seed).
---@param provider string
---@param seed string|nil
local function launch(provider, seed)
  if not vim.tbl_contains(ORDER, provider) then provider = 'browse' end
  local opts = {
    on_cycle = function() launch(next_provider(provider), nil) end,
    record   = function(query) _last = { provider = provider, query = query or '' } end,
    seed     = seed,
  }
  local has_tele = pcall(require, 'telescope')

  if provider == 'browse' then
    if has_tele then require('pkm.telescope').browse(seed, opts)
    else             require('pkm.ui').browse() end
  elseif provider == 'views' then
    require('pkm.views').popup_search(opts)
  else -- 'nav'
    require('pkm.nav').search(opts)
  end
end

M._launch = launch   -- exposed for tests

--- Open the cyclable pop-up on `provider`. <C-l> re-opens on the next provider.
--- Always a FRESH search by design (no seed) — see M.resume for going back.
---@param provider string|nil  'browse' | 'views' | 'nav' (default 'browse')
function M.open(provider)
  launch(provider, nil)
end

--- Reopen the pop-up's OWN previous search — the last provider, seeded with the
--- last typed query (Item 10). Unlike Telescope's native resume (which brings back
--- whatever picker was last, so a fresh pop-up open would shadow the real search),
--- this is pop-up-specific: `_last` is set only when a search is committed, so
--- opening the pop-up clean in between does not clear it. Falls back to Telescope's
--- native resume when nothing has been committed yet (the immediate search→resume
--- flow, before any selection). Needs Telescope either way.
function M.resume()
  local has_tele = pcall(require, 'telescope')
  if not has_tele then
    vim.notify('[pkm] resume needs Telescope', vim.log.levels.WARN)
    return
  end
  if _last and _last.query ~= '' then
    launch(_last.provider, _last.query)
  else
    require('telescope.builtin').resume()
  end
end

return M
