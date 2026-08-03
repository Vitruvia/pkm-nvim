-- =============================================================================
-- pkm.nav — current-file navigation: a heading index of the focused note
-- =============================================================================
-- Dependencies : pkm.panel, pkm.markdown (scan_headings, lazy)
-- Consumed by  : pkm.commands.panel (:PKMPanel nav), pkm.init (setup), keymaps
--
-- A persistent side panel listing the ATX headings of the markdown buffer you are
-- working in, indented by level. <CR> jumps the source window to the heading; `/`
-- filters by text; the panel follows the active note as you switch buffers. Built
-- on the generic pkm.panel factory — the same container the buffer and tag panels
-- use — so it is one content provider among others. This is Phase 3.1 of the
-- container/content work: a standalone panel that does not touch views.lua.
--
-- Public API:
--   setup(cfg)        → register the source-tracking autocmd (once)
--   toggle()          → open/close the nav panel in the current tabpage
--   is_open()         → boolean
--   refresh_if_open() → rebuild if open
-- =============================================================================

local panel = require('pkm.panel')

local M = {}

-- The markdown window/buffer the nav reflects. Updated as the user moves between
-- normal windows, so the panel always shows the note last worked in — not itself.
local _source = nil   -- { win = <winid>, buf = <bufnr> } | nil

-- =============================================================================
-- SECTION: Source tracking
-- =============================================================================

--- A normal (non-float) window showing a markdown buffer that is not a PKM panel.
---@param win integer
---@return boolean
local function eligible(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  if vim.api.nvim_win_get_config(win).relative ~= '' then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].filetype == 'markdown'
end

--- Remember `win` as the source if it is an eligible markdown window.
---@param win integer
local function capture(win)
  if eligible(win) then
    _source = { win = win, buf = vim.api.nvim_win_get_buf(win) }
  end
end

-- =============================================================================
-- SECTION: Content
-- =============================================================================

--- Strip the leading `#`s (up to three spaces of ATX indent) and trailing space.
---@param line string
---@return string
local function heading_text(line)
  return (line:gsub('^%s?%s?%s?#+%s*', ''):gsub('%s+$', ''))
end

--- Heading index of a buffer: display lines (level-indented, with a title header)
--- and a display-row → source-line map. Filtered by `query` (case-insensitive
--- substring over the heading text). Pure; exposed for tests.
---@param buf integer
---@param query string|nil
---@return string[] lines, table<integer,integer> map
local function headings_of(buf, query)
  local md    = require('pkm.markdown')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local heads = md.scan_headings(lines)
  local q     = (query or ''):lower()

  local name      = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
  local vault_ind = require('pkm.vault').indicator()
  local header    = '▚ ' .. (name ~= '' and name or '[No Name]')
  if vault_ind ~= '' then header = header .. '  · ' .. vault_ind end
  local out  = { header }   -- header; not jumpable
  local map  = {}

  for _, h in ipairs(heads) do
    local text = heading_text(lines[h.lnum] or '')
    if q == '' or text:lower():find(q, 1, true) then
      out[#out + 1] = string.rep('  ', math.max(0, h.level - 1)) .. text
      map[#out] = h.lnum
    end
  end

  if #out == 1 then   -- only the header line
    out[#out + 1] = (q == '') and '  (no headings)' or ('  (no match: ' .. tostring(query) .. ')')
  end
  return out, map
end

M._headings_of = headings_of   -- for tests

--- Panel build_lines(state): the headings of the current source buffer.
local function build_lines(state)
  if not (_source and vim.api.nvim_buf_is_valid(_source.buf)) then
    return { '  (no markdown buffer)' }, {}
  end
  return headings_of(_source.buf, state.query)
end

-- =============================================================================
-- SECTION: Keymap actions
-- =============================================================================

--- Jump the source window to the heading under the cursor.
local function on_select(state)
  local row    = vim.api.nvim_win_get_cursor(0)[1]
  local target = state.map and state.map[row]
  if not target then return end
  if not (_source and vim.api.nvim_win_is_valid(_source.win)) then
    vim.notify('[pkm] the note window is gone', vim.log.levels.WARN)
    return
  end
  vim.api.nvim_set_current_win(_source.win)
  pcall(vim.api.nvim_win_set_cursor, _source.win, { target, 0 })
  vim.cmd('normal! zz')
end

--- Prompt for a filter string and rebuild.
local function on_filter(state, helpers)
  vim.ui.input({ prompt = 'Filter headings: ', default = state.query or '' }, function(input)
    if input == nil then return end   -- cancelled
    state.query = input
    helpers.refresh()
  end)
end

--- Clear the filter and rebuild.
local function on_clear(state, helpers)
  state.query = ''
  helpers.refresh()
end

-- =============================================================================
-- SECTION: Panel + public API
-- =============================================================================

local _panel = panel.create({
  name          = 'nav',
  split_cmd     = 'noautocmd topleft vsplit',
  build_lines   = build_lines,
  win_opts      = { winfixwidth = true, cursorline = true },
  focus_on_open = true,
  refresh_events = { 'BufWinEnter', 'BufWritePost' },
  resize = function(state)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_width(state.win, require('pkm').config.sidebar_width or 30)
    end
  end,
  keymaps = {
    ['<CR>'] = on_select,
    ['/']    = on_filter,
    ['c']    = on_clear,
    ['r']    = function(_, helpers) helpers.refresh() end,
  },
})

--- Register the source-tracking autocmd (once). Called from pkm.init.setup so the
--- source is current from startup, before the panel is ever opened.
---@param _cfg table  resolved config (unused; kept for the module setup contract)
function M.setup(_cfg)
  local aug = vim.api.nvim_create_augroup('PKMNav', { clear = true })
  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter' }, {
    group    = aug,
    callback = function()
      capture(vim.api.nvim_get_current_win())
      if _panel.is_open() then vim.schedule(_panel.refresh) end
    end,
  })
end

--- Open/close the nav panel. Seeds the source from the current window first, since
--- focus_on_open moves focus to the panel before the first render.
function M.toggle()
  capture(vim.api.nvim_get_current_win())
  _panel.toggle()
end

--- Return true if the nav panel is open in the current tabpage.
---@return boolean
function M.is_open() return _panel.is_open() end

--- Rebuild the panel if it is open.
function M.refresh_if_open()
  if _panel.is_open() then _panel.refresh() end
end

return M
