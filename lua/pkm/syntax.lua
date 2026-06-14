-- =============================================================================
-- pkm.syntax — PKM-specific syntax activation
-- =============================================================================
-- Dependencies : none (tree-sitter parsers are bundled in Neovim 0.10+)
-- Consumed by  : pkm.mode
--
-- Manages PKM-specific tree-sitter syntax highlighting for markdown buffers.
-- Phase 4 stub: enable() and disable() are no-ops until the query files
-- (queries/markdown/highlights.scm, queries/markdown/injections.scm) are
-- written. The function signatures are fixed; only the bodies change in Phase 4.
--
-- Mechanism decision (recorded in CHANGELOG):
--   enable()  → vim.treesitter.start(bufnr, 'markdown') + custom captures
--   disable() → vim.treesitter.stop(bufnr) then vim.cmd('syntax on')
--               (restores Vimscript highlighting incl. after/syntax/markdown.vim)
--
-- Public API:
--   enable(bufnr)  → activate PKM tree-sitter highlighting on buffer
--   disable(bufnr) → deactivate PKM highlighting; restore Vimscript syntax
-- =============================================================================

local M = {}

-- =============================================================================
-- SECTION: Public API
-- =============================================================================

--- Activate PKM-specific tree-sitter highlighting on the given buffer.
--- Phase 4 stub — no-op until queries/markdown/highlights.scm is written.
---@param bufnr integer  Buffer handle (0 = current buffer)
---@return nil
function M.enable(bufnr)
  -- Phase 4: vim.treesitter.start(bufnr, 'markdown')
end

--- Deactivate PKM-specific highlighting and restore default Vimscript syntax.
--- Phase 4 stub — no-op until queries/markdown/highlights.scm is written.
---@param bufnr integer  Buffer handle (0 = current buffer)
---@return nil
function M.disable(bufnr)
  -- Phase 4: vim.treesitter.stop(bufnr); vim.cmd('syntax on')
end

return M
