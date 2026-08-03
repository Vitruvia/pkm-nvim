-- =============================================================================
-- pkm.syntax — facade over the extracted `pkm-syntax` plugin
-- =============================================================================
-- The markdown highlighting (list markers, citations, ((meta-comments)), YAML
-- frontmatter, and the frontmatter fold) was extracted into the standalone
-- `pkm-syntax` plugin (github.com/Vitruvia/pkm-syntax) so it can highlight any
-- markdown, be installed on its own, and grow (folding and more) independently.
--
-- pkm-nvim now DEPENDS on pkm-syntax: add it to your plugin manager as a
-- dependency of pkm-nvim. This facade re-exports the plugin unchanged, so every
-- existing caller — `require('pkm.syntax').enable/disable/refresh_fold/foldtext`
-- and the `_find_*`/pattern exports the tests use — keeps working.
--
-- Resolution is LAZY, not once-at-load. An earlier version ran
-- `pcall(require,'pkm-syntax')` a single time when this module was first required
-- and cached a no-op stub on failure — so if the plugin manager had not yet put
-- pkm-syntax on the runtimepath at that first call (e.g. pkm-syntax declared as a
-- dependency of a lazily-loaded plugin rather than of pkm-nvim), highlighting was
-- permanently disabled for the whole session. Instead, resolve on every access
-- and cache only *success*: the first time `require('pkm-syntax')` works, that
-- module is used from then on; until then each access retries. If the plugin is
-- genuinely absent, one warning is shown and every method degrades to a no-op so
-- the rest of pkm-nvim keeps working.
-- =============================================================================

local _resolved = nil   -- the real pkm-syntax module, once require() succeeds
local _warned   = false

--- Return the pkm-syntax backend, or nil if it is not installed. Retries the
--- require on every call until it succeeds, then caches the result.
---@return table|nil
local function backend()
  if _resolved then return _resolved end
  local ok, mod = pcall(require, 'pkm-syntax')
  if ok and type(mod) == 'table' then
    _resolved = mod
    return mod
  end
  if not _warned then
    _warned = true
    vim.schedule(function()
      vim.notify(
        '[pkm] the `pkm-syntax` plugin is not installed — add Vitruvia/pkm-syntax as a '
          .. 'dependency of pkm-nvim to get markdown highlighting.',
        vim.log.levels.WARN)
    end)
  end
  return nil
end

-- Proxy: forward every field access to the real backend once it resolves,
-- returning its actual value (functions AND the string / `_find_*` exports the
-- tests assert). While pkm-syntax is absent, any access yields a no-op function
-- so callers (which use these as methods) never error.
return setmetatable({}, {
  __index = function(_, key)
    local b = backend()
    if b ~= nil then return b[key] end
    return function() end
  end,
})
