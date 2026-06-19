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
--                 Conceal       — frontmatter folding: foldmethod=manual;
--                 single fold created on enable, recreated after save;
--               'markdown' injections query overridden at runtime to drop
--               markdown_inline (performance; see ensure_injection_override)
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
--   foldtext()      → fold display text for the closed frontmatter fold
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

  -- PKMCitation: Special foreground + bold so citations pop inside nested brackets.
  -- Read Special's fg at definition time; refresh via ColorScheme autocmd.
  local sp = vim.api.nvim_get_hl(0, { name = 'Special', link = false })
  if sp and sp.fg then
    vim.api.nvim_set_hl(0, 'PKMCitation', { fg = sp.fg, bold = true })
  else
    vim.api.nvim_set_hl(0, 'PKMCitation', { link = 'Special' })
  end

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

--- Compute (and cache) the frontmatter end line for a buffer.
---@param bufnr integer
---@return integer  0 if no frontmatter block
local function compute_fm_end(bufnr)
  local fm_end = vim.b[bufnr]._pkm_fm_end
  if fm_end ~= nil then return fm_end end

  fm_end = 0
  local first = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  if first == '---' then
    -- No fixed cap: cites/cited_by metadata grows without bound as notes
    -- accumulate citations, so frontmatter length isn't predictable.
    -- Read in growing chunks instead of one bulk slice of the whole
    -- buffer — cheap (usually one chunk) for ordinary notes, still
    -- correct for a frontmatter block running into the hundreds of lines.
    local total   = vim.api.nvim_buf_line_count(bufnr)
    local scanned = 1   -- line 1 already checked above
    local chunk   = 200
    while scanned < total do
      local hi    = math.min(scanned + chunk, total)
      local lines = vim.api.nvim_buf_get_lines(bufnr, scanned, hi, false)
      for i, l in ipairs(lines) do
        if l == '---' or l == '...' then
          fm_end = scanned + i
          break
        end
      end
      if fm_end > 0 then break end
      scanned = hi
      chunk   = chunk * 2
    end
  end

  vim.b[bufnr]._pkm_fm_end = fm_end
  return fm_end
end

local function setup_win_opts(win_id)
  if not vim.api.nvim_win_is_valid(win_id) then return end
  local bufnr = vim.api.nvim_win_get_buf(win_id)
  vim.api.nvim_win_call(win_id, function()
    vim.wo.foldmethod     = 'manual'
    vim.wo.foldenable     = true
    vim.wo.foldcolumn     = '0'
    vim.wo.foldtext       = "v:lua.require('pkm.syntax').foldtext()"
    vim.wo.number         = false
    vim.wo.relativenumber = false

    -- Check the window's actual fold state instead of a memoized flag — a
    -- flag keyed only by win_id survives a buffer switch in a reused window
    -- and wrongly skips creating the fold for whatever note loads next.
    local fm_end = compute_fm_end(bufnr)
    if fm_end > 0 and vim.fn.foldlevel(1) == 0 then
      vim.cmd('silent! 1,' .. fm_end .. 'fold')
      vim.cmd('silent! normal! zM')
    end
  end)
end

local function teardown_win_opts(win_id)
  if not vim.api.nvim_win_is_valid(win_id) then return end
  vim.api.nvim_win_call(win_id, function()
    vim.cmd('silent! normal! zE')
    vim.wo.foldmethod     = 'manual'
    vim.wo.foldenable     = false
    vim.wo.foldcolumn     = vim.o.foldcolumn
    vim.wo.foldtext       = ''
    vim.wo.number         = vim.o.number
    vim.wo.relativenumber = vim.o.relativenumber
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
      local win_id = tonumber(ev.match)
      teardown_win_matches(win_id)
    end,
  })

  -- Re-apply highlight groups when the colorscheme changes.
  vim.api.nvim_create_autocmd('ColorScheme', {
    group    = ag,
    callback = setup_hl_groups,
  })
end

-- =============================================================================
-- SECTION: Injection override (performance)
-- =============================================================================

-- Overrides Neovim's resolved 'markdown' injections query to drop the
-- bundled markdown_inline injection — one injection region per paragraph/
-- heading/list item, documented (:h treesitter) as running over the whole
-- buffer rather than the visible range, and confirmed as the cause of
-- editing/scroll lag on large aggregator notes. Keeps only PKM's own
-- YAML-frontmatter injection. See queries/markdown/injections.scm for the
-- full rationale and trade-off; this is a belt-and-suspenders enforcement
-- of the same change, independent of query-file extends/merge semantics.
local PKM_MARKDOWN_INJECTIONS = [=[
((minus_metadata) @injection.content
  (#set! injection.language "yaml")
  (#set! injection.include-children))
]=]

local _injections_overridden = false

local function ensure_injection_override()
  if _injections_overridden then return end
  _injections_overridden = true
  pcall(vim.treesitter.query.set, 'markdown', 'injections', PKM_MARKDOWN_INJECTIONS)
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
  return '▸ frontmatter (' .. n .. ' lines)'
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

  ensure_injection_override()

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
    callback = function()
      vim.b[bufnr]._pkm_fm_end = nil
      for _, win_id in ipairs(vim.fn.win_findbuf(bufnr)) do
        pcall(vim.api.nvim_win_call, win_id, function() vim.cmd('silent! normal! zE') end)
        setup_win_opts(win_id)
      end

      local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'markdown')
      if ok and parser then pcall(function() parser:parse(true) end) end
    end,
  })

  -- Force the *local* injected tree (the header/paragraph under the cursor)
  -- to reparse on every change, without forcing every injection in the
  -- whole document to reparse — that scales O(n) per keystroke on large
  -- aggregator notes. A full forced reparse still runs on save (below),
  -- which catches anything a margin-bounded reparse could miss (e.g. :g
  -- commands touching lines far from the cursor).
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group    = ag,
    buffer   = bufnr,
    callback = function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'markdown')
      if not (ok and parser) then return end
      local last = vim.api.nvim_buf_line_count(bufnr)
      local row  = vim.api.nvim_win_get_cursor(0)[1] - 1
      local lo, hi = math.max(row - 20, 0), math.min(row + 20, last)
      pcall(function() parser:parse({ lo, 0, hi, 0 }) end)
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
