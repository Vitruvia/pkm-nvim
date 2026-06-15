-- =============================================================================
-- pkm.syntax — PKM-specific syntax activation
-- =============================================================================
-- Dependencies : none (markdown parser bundled in Neovim 0.10+)
-- Consumed by  : pkm.mode
--
-- Manages PKM-specific tree-sitter syntax highlighting for markdown buffers.
-- Called by mode.lua on activate/deactivate; tracks state per-buffer and
-- per-window so each PKM note gets consistent highlighting.
--
-- Mechanism (recorded in CHANGELOG, Phase 4 decision):
--   enable()  → vim.treesitter.start(bufnr, 'markdown')
--               custom highlight groups loaded from:
--                 queries/markdown/highlights.scm  (indented code, list markers)
--                 queries/markdown/injections.scm  (YAML frontmatter; needs yaml parser)
--               match-based highlights via vim.fn.matchadd (per-window):
--                 PKMCitation   — note[0042], bib[...], journal[...], scratch[...]
--                 PKMMetaComment — ((text)) double-paren meta-comments (§9 conventions)
--                 Conceal       — [[ and ]] wiki-link bracket conceal
--               frontmatter folding: foldmethod=expr per-window
--
--   disable() → vim.treesitter.stop(bufnr)
--               vim.cmd('syntax on') restores Vimscript highlighting
--               matchadd IDs cleared, window options restored
--
-- Known behaviour (not a bug):
--   Text immediately followed by --- (no blank line) is a setext level-2
--   heading by CommonMark and is highlighted accordingly. Use a blank line
--   before --- to produce a thematic break instead.
--
-- Public API:
--   enable(bufnr)   → activate PKM highlighting on buffer
--   disable(bufnr)  → deactivate PKM highlighting; restore Vimscript syntax
--   foldexpr(lnum)  → fold expression for frontmatter; called by Neovim
-- =============================================================================

local M = {}

-- =============================================================================
-- SECTION: State
-- =============================================================================

-- Per-window matchadd IDs registered by this module. win_id → { id, ... }
local _win_matches = {}

-- Buffer handles with PKM highlighting active. bufnr → true
local _active_bufs = {}

-- Global autocmds (WinClosed, ColorScheme) registered only once.
local _global_autocmds_set = false

local _augroup = nil

local function get_augroup()
  if not _augroup then
    _augroup = vim.api.nvim_create_augroup('PKMSyntax', { clear = true })
  end
  return _augroup
end

-- =============================================================================
-- SECTION: Highlight groups
-- =============================================================================

--- Define all PKM-specific highlight groups.
--- Called on first enable() and on ColorScheme events so definitions survive
--- theme switches.
local function setup_hl_groups()
  -- Suppress indented_code_block colour (captured as @pkm.indented in
  -- queries/markdown/highlights.scm); link to Normal so it reads as text.
  vim.api.nvim_set_hl(0, '@pkm.indented.markdown', { link = 'Normal' })

  -- In-text citation highlight. Linked to Special; users may override.
  vim.api.nvim_set_hl(0, 'PKMCitation', { link = 'Special' })

  -- §9 meta-comment highlight: ((text)) double-paren convention.
  vim.api.nvim_set_hl(0, 'PKMMetaComment', { link = 'Comment' })

  -- YAML injection: replace distracting pink/magenta with subdued colours.
  vim.api.nvim_set_hl(0, '@property.yaml',              { link = 'Identifier' })
  vim.api.nvim_set_hl(0, '@string.yaml',                { link = 'Normal'     })
  vim.api.nvim_set_hl(0, '@punctuation.delimiter.yaml', { link = 'NonText'    })
  vim.api.nvim_set_hl(0, '@punctuation.special.yaml',   { link = 'NonText'    })
  vim.api.nvim_set_hl(0, '@boolean.yaml',               { link = 'Keyword'    })
  vim.api.nvim_set_hl(0, '@number.yaml',                { link = 'Number'     })
end

-- =============================================================================
-- SECTION: Per-window match highlights
-- =============================================================================

--- Register match-based highlights in a single window.
--- Idempotent: returns immediately if window already has PKM matches.
---@param win_id integer
local function setup_win_matches(win_id)
  if _win_matches[win_id] then return end
  if not vim.api.nvim_win_is_valid(win_id) then return end
  local ids = {}

  local function add(group, pat, priority, opts)
    local ok, id = pcall(vim.fn.matchadd, group, pat, priority, -1, opts or {})
    if ok and type(id) == 'number' and id >= 0 then
      ids[#ids + 1] = id
    end
  end

  -- Citations: note[id], bib[id], journal[id], scratch[id]
  add('PKMCitation',
    [=[\v<(note|bib|journal|scratch)\[[\w\-_]+\>]=],
    10, { window = win_id })

  -- §9 meta-comments: ((any text)) — double parentheses
  add('PKMMetaComment',
    [=[\v\(\(.{-}\)\)]=],
    10, { window = win_id })

  _win_matches[win_id] = ids
end

--- Remove match-based highlights from a window.
---@param win_id integer
local function teardown_win_matches(win_id)
  if not win_id then return end
  local ids = _win_matches[win_id]
  if not ids then return end
  for _, id in ipairs(ids) do
    pcall(vim.fn.matchdelete, id, win_id)
  end
  _win_matches[win_id] = nil
end

-- =============================================================================
-- SECTION: Per-window options
-- =============================================================================

--- Apply PKM window options: folding and wiki-link conceal.
---@param win_id integer
local function setup_win_opts(win_id)
  if not vim.api.nvim_win_is_valid(win_id) then return end
  vim.api.nvim_win_call(win_id, function()
    vim.wo.foldmethod  = 'expr'
    vim.wo.foldexpr    = "v:lua.require('pkm.syntax').foldexpr(v:lnum)"
    vim.wo.foldenable  = true
    vim.wo.foldlevel   = 0
    vim.wo.foldcolumn  = '0'
    vim.wo.foldtext    = "v:lua.require('pkm.syntax').foldtext()"
    vim.cmd('silent! normal! zM')  -- force-close frontmatter fold immediately
  end)
end

--- Restore window options changed by setup_win_opts.
---@param win_id integer
local function teardown_win_opts(win_id)
  if not vim.api.nvim_win_is_valid(win_id) then return end
  vim.api.nvim_win_call(win_id, function()
    vim.wo.foldmethod    = 'manual'
    vim.wo.foldexpr      = ''
    vim.wo.foldenable    = false
    vim.wo.foldlevel     = 0
    vim.wo.foldcolumn = vim.o.foldcolumn
    vim.wo.foldtext   = ''
  end)
end

-- =============================================================================
-- SECTION: Global autocmds (registered once)
-- =============================================================================

local function ensure_global_autocmds()
  if _global_autocmds_set then return end
  _global_autocmds_set = true
  local ag = get_augroup()

  -- Clean up per-window state when any window closes.
  vim.api.nvim_create_autocmd('WinClosed', {
    group    = ag,
    callback = function(ev)
      teardown_win_matches(tonumber(ev.match))
    end,
  })

  -- Re-apply highlight groups when the colorscheme changes.
  vim.api.nvim_create_autocmd('ColorScheme', {
    group    = ag,
    callback = setup_hl_groups,
  })
end

-- =============================================================================
-- SECTION: Fold expression
-- =============================================================================

--- Fold expression for PKM markdown frontmatter.
--- Returns '>1' for the opening --- line (starts a fold), '1' for frontmatter
--- body lines (inside the fold), '0' for everything else.
--- Caches the frontmatter end line in vim.b._pkm_fm_end per buffer;
--- cache is cleared on BufWritePost.
--- Called by Neovim as: v:lua.require('pkm.syntax').foldexpr(v:lnum)
---@param lnum integer  1-indexed line number (v:lnum)
---@return string  foldlevel expression
function M.foldexpr(lnum)
  local bufnr = vim.api.nvim_get_current_buf()

  local fm_end = vim.b[bufnr]._pkm_fm_end
  if fm_end == nil then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 100, false)
    fm_end = 0
    if lines[1] == '---' then
      for i = 2, #lines do
        if lines[i] == '---' or lines[i] == '...' then
          fm_end = i
          break
        end
      end
    end
    vim.b[bufnr]._pkm_fm_end = fm_end
  end

  if fm_end == 0    then return '0'  end
  if lnum == 1      then return '>1' end
  if lnum <= fm_end then return '1'  end
  return '0'
end

-- =============================================================================
-- SECTION: Public API
-- =============================================================================
--
--- Fold text for the closed frontmatter fold.
--- Called by Neovim as: v:lua.require('pkm.syntax').foldtext()
---@return string
function M.foldtext()
  local n = vim.v.foldend - vim.v.foldstart + 1
  return string.format('  ▸ frontmatter  (%d lines)  [za toggle · zR open all]', n)
end

--- Activate PKM-specific tree-sitter highlighting on the given buffer.
--- Idempotent: safe to call when already active.
---@param bufnr integer  Buffer handle (0 = current buffer)
---@return nil
function M.enable(bufnr)
  bufnr = (bufnr == nil or bufnr == 0)
    and vim.api.nvim_get_current_buf() or bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if _active_bufs[bufnr] then return end
  _active_bufs[bufnr] = true

  local ok, err = pcall(vim.treesitter.start, bufnr, 'markdown')
  if not ok then
    vim.notify(
      '[pkm] tree-sitter markdown parser unavailable: ' .. tostring(err),
      vim.log.levels.WARN)
    _active_bufs[bufnr] = nil
    return
  end

  setup_hl_groups()
  ensure_global_autocmds()

  -- Defer so window options are applied after tree-sitter's initial parse
  -- completes; applying them in the same tick gets reset by TS.
  vim.schedule(function()
    if not (_active_bufs[bufnr] and vim.api.nvim_buf_is_valid(bufnr)) then return end
    for _, win_id in ipairs(vim.fn.win_findbuf(bufnr)) do
      setup_win_matches(win_id)
      setup_win_opts(win_id)
    end
  end)

  local ag = get_augroup()

  vim.api.nvim_create_autocmd('BufWinEnter', {
    group    = ag,
    buffer   = bufnr,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      setup_win_matches(win)
      setup_win_opts(win)
    end,
  })

  vim.api.nvim_create_autocmd('BufWritePost', {
    group    = ag,
    buffer   = bufnr,
    callback = function() vim.b[bufnr]._pkm_fm_end = nil end,
  })

  -- Re-sync tree-sitter after undo to prevent 'end_row out of range' errors.
  vim.api.nvim_create_autocmd('UndoPost', {
    group    = ag,
    buffer   = bufnr,
    callback = function()
      vim.schedule(function()
        if _active_bufs[bufnr] and vim.api.nvim_buf_is_valid(bufnr) then
          pcall(vim.treesitter.start, bufnr, 'markdown')
        end
      end)
    end,
  })
end

--- Deactivate PKM-specific highlighting and restore default Vimscript syntax.
--- Idempotent: safe to call when already inactive.
---@param bufnr integer  Buffer handle (0 = current buffer)
---@return nil
function M.disable(bufnr)
  bufnr = (bufnr == nil or bufnr == 0)
    and vim.api.nvim_get_current_buf() or bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  _active_bufs[bufnr] = nil

  pcall(vim.treesitter.stop, bufnr)

  for _, win_id in ipairs(vim.fn.win_findbuf(bufnr)) do
    teardown_win_matches(win_id)
    teardown_win_opts(win_id)
  end

  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd('syntax on')
  end)
end

return M
