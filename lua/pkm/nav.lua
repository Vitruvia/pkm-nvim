-- =============================================================================
-- pkm.nav — current-file navigation: a heading index of the focused note
-- =============================================================================
-- Dependencies : pkm.markdown (scan_headings, lazy), pkm.vault (lazy)
-- Consumed by  : pkm.views (registers as a sidebar provider), pkm.init (setup)
--
-- A heading index of the markdown buffer you are working in, indented by level.
-- It is NOT its own container: it is a CONTENT PROVIDER on the one sidebar (the
-- container pkm.views owns). The sidebar shows either the views provider or this
-- nav provider; `:PKMPanel nav` switches the sidebar to nav, and the sidebar's
-- cycle key rotates between them. `<CR>` jumps the source window to the heading;
-- `/` filters by text. The panel follows the active markdown note as you switch
-- buffers. (Area 3, Phase 3.3a: nav folded into the one sidebar as content.)
--
-- Public API:
--   setup(cfg)         → register source tracking + register the sidebar provider
--   capture_current()  → remember the current window as the nav source
--   sidebar_provider   → the provider table consumed by pkm.views
--   _headings_of       → exposed for tests
-- =============================================================================

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

--- Remember the current window as the nav source (if eligible). Called before
--- the sidebar switches to nav, since focus moves to the sidebar first.
function M.capture_current()
  capture(vim.api.nvim_get_current_win())
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

  local name   = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
  local header = '≡ ' .. (name ~= '' and name or '[No Name]')
  -- Append the vault only when it fits the sidebar width; a long note name would
  -- otherwise push it off-screen (the author's "only if there's space").
  local vault_ind = require('pkm.vault').indicator()
  if vault_ind ~= '' then
    local width  = require('pkm').config.sidebar_width or 30
    local with_v = header .. '  · ' .. vault_ind
    if vim.fn.strdisplaywidth(with_v) <= width then header = with_v end
  end
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

--- Provider build_lines(state): the headings of the current source buffer.
local function build_lines(state)
  if not (_source and vim.api.nvim_buf_is_valid(_source.buf)) then
    return { '  (no markdown buffer)' }, {}
  end
  return headings_of(_source.buf, state.query)
end

-- =============================================================================
-- SECTION: Keymap actions (provider keymaps: fn(state, helpers))
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
-- SECTION: Sidebar provider + setup
-- =============================================================================

--- The provider table pkm.views registers and hosts on the one sidebar.
M.sidebar_provider = {
  name        = 'nav',
  label       = 'Nav',
  statusline  = '  PKM Nav  · CR jump  · / filter  · c clear  · r refresh  · q close',
  build_lines = build_lines,
  keymaps     = {
    ['<CR>'] = on_select,
    ['/']    = on_filter,
    ['c']    = on_clear,
    ['r']    = function(_, helpers) helpers.refresh() end,
  },
  --- Seed state + place the cursor on the first heading when nav becomes active.
  init      = function() return { query = '' } end,
  on_enter  = function(state)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local last = vim.api.nvim_buf_line_count(state.buf)
      vim.api.nvim_win_set_cursor(state.win, { math.min(2, last), 0 })
    end
  end,
}

--- Register source tracking and the sidebar provider. Called from pkm.init.setup
--- so the source is current from startup and the provider is available before the
--- sidebar is ever opened.
---@param _cfg table  resolved config (unused; kept for the module setup contract)
function M.setup(_cfg)
  require('pkm.views').register_sidebar_provider(M.sidebar_provider)

  local aug = vim.api.nvim_create_augroup('PKMNav', { clear = true })
  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter' }, {
    group    = aug,
    callback = function()
      capture(vim.api.nvim_get_current_win())
      vim.schedule(function()
        local views = require('pkm.views')
        -- Autoswitch (Phase 3.3b): the sidebar follows focus between views and
        -- nav. Then, while it is showing nav, keep the headings current as the
        -- source note changes (refreshing views on every move would be waste).
        views.autoswitch_tick()
        if views.sidebar_provider_is('nav') then views.refresh_sidebar_if_open() end
      end)
    end,
  })
end

return M
