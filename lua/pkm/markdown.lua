-- =============================================================================
-- pkm.markdown — facade over the extracted `pkm-markdown` plugin
-- =============================================================================
-- The markdown editing utilities (header duplication/shift, ordered- and
-- legal-list renumbering, ordered↔unordered conversion, structure-aware reflow,
-- the ordered-list `<CR>` continuation, and `formatexpr`) were extracted into
-- the standalone `pkm-markdown` plugin (github.com/Vitruvia/pkm-markdown) so
-- they can edit any markdown, be installed on their own, and grow independently.
--
-- pkm-nvim now DEPENDS on pkm-markdown: add it to your plugin manager as a
-- dependency of pkm-nvim (alongside pkm-syntax). This facade re-exports the
-- plugin unchanged, so every existing caller — `require('pkm.markdown').<fn>`
-- across the commands, keymaps, mode, nav and notes modules, and the functions
-- the tests assert — keeps working with no change.
--
-- Resolution is LAZY, not once-at-load (the pkm.syntax lesson): an earlier
-- extraction cached a no-op stub the first time `require` failed, permanently
-- disabling the feature if the plugin manager had not yet put the sibling on the
-- runtimepath at that first call. Instead, resolve on every access and cache only
-- *success*: the first time `require('pkm-markdown')` works, that module is used
-- from then on; until then each access retries. If the plugin is genuinely
-- absent, one warning is shown and every method degrades to a no-op so the rest
-- of pkm-nvim keeps working.
-- =============================================================================

local _resolved = nil   -- the real pkm-markdown module, once require() succeeds
local _warned   = false

--- Return the pkm-markdown backend, or nil if it is not installed. Retries the
--- require on every call until it succeeds, then caches the result.
---@return table|nil
local function backend()
  if _resolved then return _resolved end
  local ok, mod = pcall(require, 'pkm-markdown')
  if ok and type(mod) == 'table' then
    _resolved = mod
    return mod
  end
  if not _warned then
    _warned = true
    vim.schedule(function()
      vim.notify(
        '[pkm] the `pkm-markdown` plugin is not installed — add Vitruvia/pkm-markdown as a '
          .. 'dependency of pkm-nvim to get markdown editing (renumber, wrap, list <CR>).',
        vim.log.levels.WARN)
    end)
  end
  return nil
end

-- Proxy: forward every field access to the real backend once it resolves,
-- returning its actual value (functions AND any non-function exports). While
-- pkm-markdown is absent, any access yields a no-op function so callers (which
-- use these as methods) never error.
local facade = setmetatable({}, {
  __index = function(_, key)
    local b = backend()
    if b ~= nil then return b[key] end
    return function() end
  end,
})

-- `formatexpr` is the one export invoked through Vim's `v:lua`, not plain Lua:
-- `formatexpr = "v:lua.require('pkm.markdown').formatexpr()"` (mode.lua). Neovim's
-- `v:lua.require('mod').field` does a RAW field lookup on the require result — it
-- does NOT honour `__index` (unlike a normal Lua `require('mod').field` call, and
-- unlike a `v:lua.Global.field` path, both of which do). So the proxy's `__index`
-- is invisible to it: `.formatexpr` would read nil, Vim would silently fall back
-- to its internal formatter, and gq/gw would stop routing through the
-- structure-aware wrap. Define it as a REAL key so v:lua's raw lookup finds it.
---@return integer  0 = handled, 1 = fall back to Vim's internal formatter
function facade.formatexpr()
  local b = backend()
  if b ~= nil then return b.formatexpr() end
  return 1  -- pkm-markdown absent: let Vim format internally rather than no-op
end

return facade
