-- =============================================================================
-- pkm.panel — Generic panel infrastructure
-- =============================================================================
-- Dependencies : none
-- Consumed by  : pkm.ui (buffer panel, tag panel); future panels (trash-restore,
--                views) per the v1.6.0 Release Plan
--
-- A "panel" is a persistent, per-tabpage split window over a scratch buffer.
-- panel.create(spec) returns a new, independent panel OBJECT — each call
-- owns its own per-tab state table (keyed by nvim_get_current_tabpage()), so
-- multiple distinct panels built on this same factory never collide.
--
-- Every panel gets, uniformly:
--   - winfixbuf = true (always, non-optional — the whole point of this
--     module existing is that every PKM panel gets this safety net without
--     each caller having to remember it)
--   - a scoped augroup: caller-specified refresh_events (debounced via
--     vim.schedule), a WinClosed safety net calling ensure_main_window()
--     after any window closes in the tabpage, BufWipeout cleanup, and
--     TabClosed pruning of dead per-tab state
--   - buffer-local keymaps supplied by the caller, invoked as
--     fn(state, helpers) — helpers = { refresh, close, ensure_main_window,
--     restore_focus } — so keymap bodies never need to reach into this
--     module's internals. restore_focus(state?) takes the keymap's own
--     `state` argument explicitly when called after close(): closing a
--     panel's bufhidden=wipe buffer fires BufWipeout synchronously, which
--     clears this panel's _tabs entry before close() returns — a fresh
--     get_tab() call at that point would return a brand-new empty table,
--     not the one holding prev_win. Passing the already-captured `state`
--     (a stable reference regardless of what _tabs[id] gets reassigned to
--     afterward) sidesteps that. Omit the argument when calling before any
--     close() in the same handler — it falls back to get_tab() safely.
--
-- Deliberately NOT unified across panels (per the v1.6.0 design discussion):
-- header/statusline hint text, content formatting, and search/filter
-- behaviour. Panels differ enough in these that forcing a shared format
-- would fight their actual differences rather than their actual similarity
-- (window/buffer/augroup lifecycle, which genuinely is uniform).
--
-- Public API:
--   create(spec) → panel object: { open(init?), close(), toggle(init?),
--                  refresh(), is_open(), get_win() }
-- =============================================================================

local M = {}

-- =============================================================================
-- SECTION: Factory
-- =============================================================================

--- Create a new, independent panel instance.
---@param spec table {
---   name           : string   required; augroup naming + 'pkm-<name>' filetype
---   split_cmd      : string   required; e.g. 'noautocmd botright split'
---   build_lines    : function(state) -> lines:string[], row_map:table
---                    row_map is opaque to this module; stored on
---                    state.map for keymap callbacks to read.
---   keymaps        : table<string, function(state, helpers)>|nil
---                    buffer-local normal-mode maps. 'q'/'<Esc>' default to
---                    close() unless the caller supplies its own.
---   refresh_events : string[]|nil  autocmd events triggering a
---                    schedule-debounced refresh; default {}
---   win_opts       : table|nil  merged over the always-on defaults
---                    (winfixbuf=true, wrap=false, number=false,
---                    cursorline=true, signcolumn='no')
---   resize         : function(state, lines)|nil  called after every
---                    populate; caller performs its own window resize
---                    (nvim_win_set_height/width) or does nothing
---   focus_on_open  : boolean|nil  default false. false = bufpanel-style:
---                    focus returns to the pre-open window immediately
---                    (glanceable, not modal). true = tagpanel-style: focus
---                    stays on the panel so the user can act on it right
---                    away; state.prev_win is always captured regardless,
---                    for helpers.restore_focus().
--- }
---@return table panel  { open, close, toggle, refresh, is_open, get_win }
function M.create(spec)
  assert(type(spec.name) == 'string' and spec.name ~= '', 'panel.create: name is required')
  assert(type(spec.split_cmd) == 'string', 'panel.create: split_cmd is required')
  assert(type(spec.build_lines) == 'function', 'panel.create: build_lines is required')

  local filetype        = 'pkm-' .. spec.name
  local keymaps          = spec.keymaps or {}
  local refresh_events   = spec.refresh_events or {}
  local extra_win_opts   = spec.win_opts or {}

  -- Per-tab state, scoped to this panel instance only.
  local _tabs = {}

  local function get_tab()
    local id = vim.api.nvim_get_current_tabpage()
    if not _tabs[id] then
      _tabs[id] = { win = nil, buf = nil, augroup = nil, map = {}, prev_win = nil }
    end
    return _tabs[id]
  end

  --- Ensure at least one main editing window exists alongside this panel.
  --- Prevents the panel from becoming the tabpage's sole non-float window.
  local function ensure_main_window()
    local t = get_tab()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= t.win and vim.api.nvim_win_get_config(win).relative == '' then
        return
      end
    end
    if t.win and vim.api.nvim_win_is_valid(t.win) then
      local cur = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(t.win)
      vim.cmd('noautocmd aboveleft new')
      vim.bo.bufhidden = 'wipe'
      if vim.api.nvim_win_is_valid(cur) then
        vim.api.nvim_set_current_win(cur)
      end
    end
  end

  local panel = {}

  --- Repopulate this panel's buffer from build_lines(state). No-op if not open.
  function panel.refresh()
    local t = get_tab()
    if not t.buf or not vim.api.nvim_buf_is_valid(t.buf) then return end
    local lines, row_map = spec.build_lines(t)
    t.map = row_map or {}
    vim.api.nvim_set_option_value('modifiable', true,  { buf = t.buf })
    vim.api.nvim_buf_set_lines(t.buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = t.buf })
    if spec.resize then spec.resize(t, lines) end
  end

  --- Close this panel's window in the current tabpage, if open.
  function panel.close()
    local t = get_tab()
    if t.win and vim.api.nvim_win_is_valid(t.win) then
      vim.api.nvim_win_close(t.win, true)
    end
  end

  local function restore_focus(explicit_state)
    local t = explicit_state or get_tab()
    if t.prev_win and vim.api.nvim_win_is_valid(t.prev_win) then
      vim.api.nvim_set_current_win(t.prev_win)
    end
  end

  local helpers = {
    refresh            = function() panel.refresh() end,
    close              = function() panel.close() end,
    ensure_main_window = ensure_main_window,
    restore_focus      = restore_focus,
  }

  --- Return true if this panel is open in the current tabpage.
  ---@return boolean
  function panel.is_open()
    local t = get_tab()
    return t.win ~= nil and vim.api.nvim_win_is_valid(t.win)
  end

  --- Return this panel's window handle in the current tabpage, or nil.
  ---@return integer|nil
  function panel.get_win()
    local t = get_tab()
    if t.win and vim.api.nvim_win_is_valid(t.win) then return t.win end
    return nil
  end

  --- Open this panel in the current tabpage, creating it if necessary.
  --- If already open, merges `init` into state and refreshes in place
  --- (does not close/reopen) — lets callers switch mode without a visible
  --- flicker, e.g. the tag panel switching between add/remove.
  ---@param init table|nil  Shallow-merged onto this tabpage's state before
  ---                        the first populate.
  function panel.open(init)
    local t = get_tab()
    local my_tab_id = vim.api.nvim_get_current_tabpage()

    if t.win and not vim.api.nvim_win_is_valid(t.win) then
      if t.augroup then pcall(vim.api.nvim_del_augroup_by_id, t.augroup) end
      _tabs[my_tab_id] = nil
      t = get_tab()
    end

    if t.win then
      if init then for k, v in pairs(init) do t[k] = v end end
      panel.refresh()
      if spec.focus_on_open then
        vim.api.nvim_set_current_win(t.win)
      end
      return
    end

    local prev_win = vim.api.nvim_get_current_win()
    t.prev_win = prev_win
    if init then for k, v in pairs(init) do t[k] = v end end

    vim.cmd(spec.split_cmd)
    t.win = vim.api.nvim_get_current_win()

    local buf = vim.api.nvim_create_buf(false, true)
    t.buf = buf
    vim.api.nvim_win_set_buf(t.win, buf)

    local win_opts = {
      winfixbuf = true, wrap = false,
      number = false, cursorline = true, signcolumn = 'no',
    }
    for k, v in pairs(extra_win_opts) do win_opts[k] = v end
    for opt, val in pairs(win_opts) do
      vim.api.nvim_set_option_value(opt, val, { win = t.win })
    end

    for opt, val in pairs({
      bufhidden = 'wipe', buftype = 'nofile', swapfile = false,
    }) do
      vim.api.nvim_set_option_value(opt, val, { buf = buf })
    end
    vim.api.nvim_set_option_value('filetype', filetype, { buf = buf })

    panel.refresh()

    t.augroup = vim.api.nvim_create_augroup(
      'PKMPanel_' .. spec.name .. '_' .. my_tab_id, { clear = true })

    for _, event in ipairs(refresh_events) do
      vim.api.nvim_create_autocmd(event, {
        group    = t.augroup,
        callback = function() vim.schedule(panel.refresh) end,
      })
    end

    vim.api.nvim_create_autocmd('WinClosed', {
      group    = t.augroup,
      callback = function()
        vim.schedule(function()
          if t.win and vim.api.nvim_win_is_valid(t.win) then
            ensure_main_window()
          end
        end)
      end,
    })

    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer   = buf,
      once     = true,
      callback = function()
        local old_t = _tabs[my_tab_id]
        if old_t and old_t.augroup then
          pcall(vim.api.nvim_del_augroup_by_id, old_t.augroup)
        end
        _tabs[my_tab_id] = nil
      end,
    })

    local ko = { noremap = true, silent = true, buffer = buf }
    for lhs, fn in pairs(keymaps) do
      vim.keymap.set('n', lhs, function()
        fn(get_tab(), helpers)
      end, ko)
    end
    if not keymaps['q'] then
      vim.keymap.set('n', 'q', function() panel.close() end, ko)
    end
    if not keymaps['<Esc>'] then
      vim.keymap.set('n', '<Esc>', function() panel.close() end, ko)
    end

    if not spec.focus_on_open then
      vim.api.nvim_set_current_win(prev_win)
    end
  end

  --- Toggle this panel: close if open, open (with init) if closed.
  ---@param init table|nil
  function panel.toggle(init)
    if panel.is_open() then
      panel.close()
    else
      panel.open(init)
    end
  end

  -- Per-instance TabClosed pruning, registered once at creation time —
  -- independent of whether the panel is currently open in any tab.
  local tabs_augroup = vim.api.nvim_create_augroup(
    'PKMPanelTabs_' .. spec.name, { clear = true })
  vim.api.nvim_create_autocmd('TabClosed', {
    group    = tabs_augroup,
    callback = function()
      local live = {}
      for _, tp in ipairs(vim.api.nvim_list_tabpages()) do live[tp] = true end
      for id in pairs(_tabs) do
        if not live[id] then _tabs[id] = nil end
      end
    end,
  })

  return panel
end

return M
