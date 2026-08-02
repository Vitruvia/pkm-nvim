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
-- If pkm-syntax is not installed, this degrades gracefully: one warning, and a
-- no-op stub so the rest of pkm-nvim keeps working (without highlighting) rather
-- than erroring on load.
-- =============================================================================

local ok, syntax = pcall(require, 'pkm-syntax')
if ok then return syntax end

vim.schedule(function()
  vim.notify(
    '[pkm] the `pkm-syntax` plugin is not installed — add Vitruvia/pkm-syntax as a '
      .. 'dependency of pkm-nvim to get markdown highlighting.',
    vim.log.levels.WARN)
end)

-- No-op stub: any method (enable, disable, refresh_fold, foldtext, …) is a
-- function that does nothing, so callers never error when the plugin is absent.
return setmetatable({}, { __index = function() return function() end end })
