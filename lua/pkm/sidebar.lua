-- =============================================================================
-- pkm.sidebar — the persistent sidebar CONTAINER (host for pluggable providers)
-- =============================================================================
-- Dependencies : pkm.panel, pkm.utils  (pkm.index / pkm.nav / pkm required lazily)
-- Consumed by  : pkm.views (registers the `views` provider + re-exports this API),
--                pkm.nav (registers the `nav` provider), commands/panel, keymaps,
--                mode, api, trash.
--
-- The sidebar is a single managed-width left split (built on pkm.panel) that
-- shows one content PROVIDER at a time. Neither `views` nor `nav` is built in
-- here: each registers itself via register_sidebar_provider() at setup, so this
-- module never depends on a provider's internals (the dependency runs one way,
-- provider → sidebar). Switching provider swaps the buffer-local keymaps
-- (teardown by lhs, then apply) and re-dispatches build_lines — no close/reopen,
-- so it never flickers.
--
-- A provider is a table:
--   { name, label, statusline, build_lines(state)->lines,
--     apply(buf)->lhs | keymaps = { lhs -> fn(state, helpers) },
--     init()->table? , on_enter(state)? }
--
-- Public API (also re-exported from pkm.views for backward compatibility):
--   get_state() / is_sidebar_open() / get_sidebar_win()          → container query
--   open(init) / close() / refresh() / refresh_sidebar_if_open() → container ops
--   register_sidebar_provider(p)                                 → add a provider
--   sidebar_provider() / sidebar_provider_is(name)               → active provider
--   set_sidebar_provider / cycle_sidebar_provider / show_sidebar_provider
--   win_is_markdown(win)                                         → focus helper
--   autoswitch_tick() / set_autoswitch(arg) / autoswitch_enabled()
--   setup()  → read config.sidebar_autoswitch (call once at plugin setup)
-- =============================================================================

local M = {}

local panel = require('pkm.panel')
local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: Container state
-- =============================================================================

-- The panel instance is created at the bottom of this file; forward-declared so
-- the API and the on_open decoration can reference it. Its per-tab state table
-- carries the provider fields — provider, mode, name, paths, tree, header_count,
-- view_lines, history, type_filter, marked — alongside the panel's own
-- win/buf/augroup, so there is one per-tabpage state and no cross-tab conflict.
local _panel

-- Sidebar autoswitch (Phase 3.3b): follow focus between the views and nav
-- providers. Default on; set from config.sidebar_autoswitch in M.setup(), toggled
-- by :PKMPanel autoswitch.
local _autoswitch_enabled = true

--- The sidebar's live per-tab state while it is open here, or nil when closed.
--- A thin alias over the panel so the in-panel keymaps read `get_tab()`. Returns
--- nil when the sidebar is closed, so the callers that can run while closed guard.
local function get_tab()
  return _panel.get_state()
end

-- =============================================================================
-- SECTION: Container query + ops (thin panel wrappers)
-- =============================================================================

--- The panel's per-tab state, or nil when the sidebar is closed here.
---@return table|nil
function M.get_state() return _panel.get_state() end

--- Is the sidebar currently open in the current tabpage?
---@return boolean
function M.is_sidebar_open() return _panel ~= nil and _panel.is_open() end

--- The sidebar window handle for the current tabpage, or nil if closed.
---@return integer|nil
function M.get_sidebar_win() return _panel and _panel.get_win() or nil end

--- Open the sidebar with the given initial per-tab state.
---@param init table
function M.open(init) return _panel.open(init) end

--- Close the sidebar in the current tabpage.
function M.close() return _panel.close() end

--- Rebuild the sidebar content in the current tabpage.
function M.refresh() return _panel.refresh() end

--- Refresh the sidebar content in every tabpage where it is open. No-op
--- otherwise. Call after any operation that modifies the note list (deletion,
--- rename, etc.). Marks (keyed by path) survive the rebuild.
function M.refresh_sidebar_if_open() _panel.refresh_all() end

-- =============================================================================
-- SECTION: Provider registry (views + nav) on the one container
-- =============================================================================

local _sidebar_providers        -- name -> provider; empty until providers register
local _sidebar_order = { 'views', 'nav' }
local _sidebar_helpers = { refresh = function() _panel.refresh() end }

--- The provider registry (empty until a provider registers itself at setup).
local function sidebar_providers()
  if not _sidebar_providers then _sidebar_providers = {} end
  return _sidebar_providers
end

--- Register a content provider (views, nav) the sidebar can host. Called at setup.
---@param provider table
function M.register_sidebar_provider(provider)
  sidebar_providers()[provider.name] = provider
end

--- The panel's build_lines: dispatch to the active provider's builder.
local function sidebar_build(state)
  return sidebar_providers()[state.provider or 'views'].build_lines(state)
end

--- Apply a provider's keymaps to `buf`; return the lhs set (for later teardown).
---@param buf integer
---@param provider table
---@return string[] lhs
local function apply_provider_keymaps(buf, provider)
  if provider.apply then return provider.apply(buf) end
  local ko  = { noremap = true, silent = true, buffer = buf }
  local lhs = {}
  for k, fn in pairs(provider.keymaps or {}) do
    vim.keymap.set('n', k, function() fn(get_tab(), _sidebar_helpers) end, ko)
    lhs[#lhs + 1] = k
  end
  return lhs
end

--- Set the sidebar window's statusline from the active provider.
---@param t table  panel state
local function set_sidebar_statusline(t)
  if not (t and t.win and vim.api.nvim_win_is_valid(t.win)) then return end
  local provider = sidebar_providers()[t.provider or 'views']
  vim.api.nvim_set_option_value('statusline', provider.statusline or '', { win = t.win })
end

--- Is the sidebar open here and showing provider `name`?
---@param name string
---@return boolean
function M.sidebar_provider_is(name)
  local t = _panel and _panel.get_state()
  return t ~= nil and (t.provider or 'views') == name
end

--- The active sidebar provider name, or nil when the sidebar is closed.
---@return string|nil
function M.sidebar_provider()
  local t = _panel and _panel.get_state()
  return t and (t.provider or 'views') or nil
end

--- Switch the OPEN sidebar to provider `name` in place (swap keymaps + rebuild).
--- No-op if closed or already on `name`.
---@param name string
function M.set_sidebar_provider(name)
  local t = _panel.get_state()
  if not t or (t.provider or 'views') == name then return end
  local provider = sidebar_providers()[name]
  if not provider then return end
  if t._applied_lhs then
    for _, k in ipairs(t._applied_lhs) do
      pcall(vim.keymap.del, 'n', k, { buffer = t.buf })
    end
  end
  t.provider = name
  if provider.init then for k, v in pairs(provider.init()) do t[k] = v end end
  if name == 'views' then
    t.mode    = t.mode or 'overview'
    t.marked  = t.marked or {}
    t.history = t.history or {}
  end
  t._applied_lhs = apply_provider_keymaps(t.buf, provider)
  set_sidebar_statusline(t)
  _panel.refresh()
  if provider.on_enter then provider.on_enter(t) end
end

--- Cycle the open sidebar to the next registered provider (views <-> nav).
function M.cycle_sidebar_provider()
  if not _panel.is_open() then return end
  local cur = _panel.get_state().provider or 'views'
  local i = 1
  for idx, n in ipairs(_sidebar_order) do if n == cur then i = idx; break end end
  M.set_sidebar_provider(_sidebar_order[(i % #_sidebar_order) + 1])
end

--- Show provider `name` in the sidebar: open it on that provider if closed,
--- switch to it if open on another, toggle it closed if already on it.
---@param name string
function M.show_sidebar_provider(name)
  local provider = sidebar_providers()[name]
  if not provider then return end
  if not _panel.is_open() then
    if name == 'nav' then require('pkm.nav').capture_current() end
    local init = { provider = name }
    if provider.init then for k, v in pairs(provider.init()) do init[k] = v end end
    if name == 'views' then
      init.mode = 'overview'; init.marked = {}; init.history = {}; init.type_filter = nil
    end
    _panel.open(init)
    local t = _panel.get_state()
    if t then
      set_sidebar_statusline(t)
      if provider.on_enter then provider.on_enter(t) end
    end
    return
  end
  local t = _panel.get_state()
  if (t.provider or 'views') == name then _panel.close(); return end
  if name == 'nav' then require('pkm.nav').capture_current() end
  M.set_sidebar_provider(name)
end

-- =============================================================================
-- SECTION: Autoswitch (Phase 3.3b)
-- =============================================================================
--
-- With autoswitch on, the open sidebar follows focus LIVE: whenever a real
-- editing window is focused it shows `nav` for a markdown file and `views` for
-- anything else. A manual <C-n> cycle is a transient peek — it holds while you
-- stay in the sidebar (focusing the sidebar is ignored) and reverts the next
-- time you focus an editing window. To pin the sidebar to one provider, turn
-- autoswitch off (:PKMPanel autoswitch off).

--- A normal (non-float) window showing a markdown buffer.
---@param win integer
---@return boolean
function M.win_is_markdown(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  if vim.api.nvim_win_get_config(win).relative ~= '' then return false end
  return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'markdown'
end

--- The provider the current focus asks for, or nil for "leave as is" (the
--- sidebar itself, another PKM panel, netrw, or a floating window is focused —
--- none of those is the note you are working in).
---@return 'nav'|'views'|nil
local function autoswitch_desired()
  local cur = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(cur) then return nil end
  if vim.api.nvim_win_get_config(cur).relative ~= '' then return nil end   -- a float
  if _panel.get_win() == cur then return nil end                           -- the sidebar
  local ft = vim.bo[vim.api.nvim_win_get_buf(cur)].filetype
  if ft == 'pkm-sidebar' or ft == 'pkm-bufpanel' or ft == 'netrw' then return nil end
  if ft == 'markdown' then return 'nav' end
  return 'views'
end

--- React to a focus change: set the open sidebar to the provider the focused
--- editing window asks for. No-op when autoswitch is off, the sidebar is closed,
--- a non-editing window is focused, or the provider is already what the context
--- wants. Called (scheduled) from nav's window tracker.
function M.autoswitch_tick()
  if not _autoswitch_enabled or not _panel.is_open() then return end
  local desired = autoswitch_desired()
  if not desired then return end
  local t = _panel.get_state()
  if not t or (t.provider or 'views') == desired then return end
  if desired == 'nav' then require('pkm.nav').capture_current() end
  M.set_sidebar_provider(desired)
end

--- Turn sidebar autoswitch on / off / toggle (default toggle). Applying it on
--- re-checks the current context immediately.
---@param arg string|nil  'on' | 'off' | 'toggle'
---@return boolean enabled
function M.set_autoswitch(arg)
  arg = (arg == '' and 'toggle') or arg or 'toggle'
  if arg == 'on' then
    _autoswitch_enabled = true
  elseif arg == 'off' then
    _autoswitch_enabled = false
  else
    _autoswitch_enabled = not _autoswitch_enabled
  end
  vim.notify('[pkm] sidebar autoswitch: ' .. (_autoswitch_enabled and 'on' or 'off'),
    vim.log.levels.INFO)
  if _autoswitch_enabled then M.autoswitch_tick() end
  return _autoswitch_enabled
end

--- Is sidebar autoswitch currently enabled?
---@return boolean
function M.autoswitch_enabled()
  return _autoswitch_enabled
end

-- =============================================================================
-- SECTION: The container — decorations, keymaps, and the panel instance
-- =============================================================================

--- The sidebar's decorations + common keymaps, run once per open by pkm.panel.
--- Provider-specific keymaps for the ACTIVE provider are applied here and swapped
--- later by set_sidebar_provider. q/<Esc> close and <C-n> cycles providers —
--- those are common to every provider and owned here so they survive a switch.
---@param pstate table  the panel's per-tab state; pstate.win / pstate.buf live
local function sidebar_on_open(pstate, _helpers)
  local buf = pstate.buf

  -- Statusline hint (provider-aware; re-asserted after focus moves).
  local function refresh_sl()
    vim.schedule(function() set_sidebar_statusline(get_tab() or pstate) end)
  end
  refresh_sl()
  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter' }, {
    buffer = buf, callback = refresh_sl,
  })

  local ko = { noremap = true, silent = true, buffer = buf }

  -- q / <Esc>: close (common). Quit gracefully if the sidebar is the sole window.
  local function close_sidebar()
    local ct = get_tab()
    if not (ct and ct.win and vim.api.nvim_win_is_valid(ct.win)) then return end
    local non_float = 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).relative == '' then non_float = non_float + 1 end
    end
    if non_float <= 1 then vim.cmd('quit') else vim.api.nvim_win_close(ct.win, true) end
  end
  vim.keymap.set('n', 'q',     close_sidebar, ko)
  vim.keymap.set('n', '<Esc>', close_sidebar, ko)

  -- <C-n>: cycle the sidebar's content provider (views <-> nav).
  vim.keymap.set('n', '<C-n>', function() M.cycle_sidebar_provider() end, ko)

  -- winbar infobar (VIEWS provider only): the note under the cursor as
  -- title · filename-with-number. nav shows its file in its own header row.
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    callback = function()
      local ct = get_tab()
      if not (ct and ct.win and vim.api.nvim_win_is_valid(ct.win)) then return end
      local winbar = ''
      if (ct.provider or 'views') == 'views' and ct.mode == 'detail' then
        local row = vim.api.nvim_win_get_cursor(ct.win)[1]
        local idx = row - ct.header_count
        if idx >= 1 and idx <= #ct.paths then
          winbar = utils.winbar_label(require('pkm.index').get(ct.paths[idx]), ct.paths[idx])
        else
          local filter_label = ct.type_filter and ('  [' .. ct.type_filter .. ']') or ''
          winbar = ' ≡ ' .. (ct.name or '') .. filter_label
        end
      end
      vim.api.nvim_set_option_value('winbar', winbar, { win = ct.win })
    end,
  })

  -- Apply the active provider's keymaps for this open.
  pstate._applied_lhs = apply_provider_keymaps(buf, sidebar_providers()[pstate.provider or 'views'])
end

-- The sidebar container: a managed-width left split on pkm.panel. Provider
-- state (mode/name/paths/marked/history/type_filter) rides the panel's per-tab
-- table; the content builder is sidebar_build(); the interactive surface is
-- sidebar_on_open(). focus_on_open keeps the sidebar focused after opening.
_panel = panel.create({
  name          = 'sidebar',
  split_cmd     = 'noautocmd topleft vsplit',
  width         = function() return require('pkm').config.sidebar_width or 40 end,
  win_opts      = { winfixwidth = true },
  build_lines   = sidebar_build,
  on_open       = sidebar_on_open,
  focus_on_open = true,
})

-- =============================================================================
-- SECTION: Setup
-- =============================================================================

--- Read config once at plugin setup. Autoswitch defaults on; opt out with
--- config.sidebar_autoswitch = false.
function M.setup()
  _autoswitch_enabled = require('pkm').config.sidebar_autoswitch ~= false
end

return M
