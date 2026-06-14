-- =============================================================================
-- pkm.mode — PKMMode session context manager
-- =============================================================================
-- Dependencies : pkm.views (lazy), pkm.ui (lazy), pkm.index (lazy),
--                pkm.syntax (lazy), pkm.utils
-- Consumed by  : pkm.init (setup), pkm.commands (:PKMMode, :PKMExplorer)
--
-- Manages the PKM editing context: explorer UI (sidebar + bufpanel), eager
-- index pre-build, and syntax activation. Mode state is session-scoped and
-- independent of individual panel visibility.
--
-- Trigger behaviour (configured in config.pkm_mode.triggers):
--   open_note : activate when a PKM note is opened (BufReadPost).
--               If mode is already active, only enables syntax on the new buffer.
--   enter_dir : activate when CWD is or becomes the PKM root (DirChanged +
--               startup check at setup() time).
--
-- State model:
--   _active is a session boolean independent of panel state. Activation is
--   idempotent: calling activate() when already active opens any panels that
--   were manually closed, without resetting sidebar content or erroring.
--   Deactivation is idempotent: calling deactivate() when inactive is a no-op.
--   Manual panel closure does not change _active.
--
-- Public API:
--   setup(config)  → register trigger autocmds; run startup dir check
--   activate()     → open explorer, prebuild index, enable syntax
--   deactivate()   → close explorer, disable syntax
--   toggle()       → activate if inactive; deactivate if active
--   set(state)     → activate if state='on'; deactivate if state='off'
--   is_active()    → boolean
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: State
-- =============================================================================

local _active = false
local _config = nil   -- resolved pkm_mode subtable; set in setup()

-- =============================================================================
-- SECTION: Internal helpers
-- =============================================================================

--- Return true if path is inside the PKM root.
---@param path string  Absolute path, any separator
---@return boolean
local function is_pkm_file(path)
  if not _config then return false end
  local root = require('pkm').config.root_path:gsub('\\', '/'):gsub('[/\\]+$', '')
  local p    = path:gsub('\\', '/')
  return p:lower():sub(1, #root + 1) == root:lower() .. '/'
end

--- Return true if cwd is the PKM root or a subdirectory of it.
---@return boolean
local function cwd_is_pkm()
  if not _config then return false end
  local root = require('pkm').config.root_path:gsub('\\', '/'):gsub('[/\\]+$', '')
  local cwd  = vim.fn.getcwd():gsub('\\', '/')
  return cwd:lower() == root:lower()
      or cwd:lower():sub(1, #root + 1) == root:lower() .. '/'
end

--- Enable PKM syntax on every listed PKM buffer currently open.
local function syntax_enable_all()
  local syntax = require('pkm.syntax')
  local root   = require('pkm').config.root_path:gsub('\\', '/'):gsub('[/\\]+$', '')
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(bufnr):gsub('\\', '/')
      if name:lower():sub(1, #root + 1) == root:lower() .. '/' then
        syntax.enable(bufnr)
      end
    end
  end
end

--- Disable PKM syntax on every listed PKM buffer currently open.
local function syntax_disable_all()
  local syntax = require('pkm.syntax')
  local root   = require('pkm').config.root_path:gsub('\\', '/'):gsub('[/\\]+$', '')
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr):gsub('\\', '/')
      if name:lower():sub(1, #root + 1) == root:lower() .. '/' then
        syntax.disable(bufnr)
      end
    end
  end
end

-- =============================================================================
-- SECTION: Setup
-- =============================================================================

--- Register trigger autocmds and run startup CWD check.
--- Must be called from pkm.init.setup() after config is resolved.
---@param cfg table  Resolved PKM config (the full config table)
---@return nil
function M.setup(cfg)
  _config = cfg.pkm_mode

  local augroup = vim.api.nvim_create_augroup('PKMMode', { clear = true })

  -- open_note trigger: activate when a PKM file is opened.
  vim.api.nvim_create_autocmd('BufReadPost', {
    group    = augroup,
    callback = function()
      if not _config.triggers.open_note then return end
      local path = vim.fn.expand('<afile>:p')
      if not is_pkm_file(path) then return end
      if not _active then
        M.activate()
      else
        -- Mode already active; enable syntax on the newly opened buffer.
        if _config.syntax.enabled then
          require('pkm.syntax').enable(vim.api.nvim_get_current_buf())
        end
      end
    end,
  })

  -- enter_dir trigger: activate when CWD changes to PKM root.
  vim.api.nvim_create_autocmd('DirChanged', {
    group    = augroup,
    callback = function()
      if not _config.triggers.enter_dir then return end
      if cwd_is_pkm() and not _active then M.activate() end
    end,
  })

  -- Startup check: activate immediately if Neovim was opened from PKM root.
  if _config.triggers.enter_dir and cwd_is_pkm() then
    vim.schedule(function() M.activate() end)
  end
end

-- =============================================================================
-- SECTION: Public API
-- =============================================================================

--- Activate PKM mode. Idempotent: safe to call when already active.
--- Opens any closed explorer panels, pre-builds the index if configured,
--- and enables PKM syntax on all open PKM buffers.
---@return nil
function M.activate()
  _active = true

  local views = require('pkm.views')
  local ui    = require('pkm.ui')

  if _config.layout.sidebar and not views.is_sidebar_open() then
    views.open_sidebar()
  end

  if _config.layout.bufpanel and not ui.is_bufpanel_open() then
    ui.toggle_bufpanel()
  end

  if _config.index.prebuild and not require('pkm.index').is_built() then
    vim.schedule(function() require('pkm.index').rebuild() end)
  end

  if _config.syntax.enabled then syntax_enable_all() end

  vim.notify('[pkm] PKM mode on', vim.log.levels.INFO)
end

--- Deactivate PKM mode. Idempotent: safe to call when already inactive.
--- Closes open explorer panels and disables PKM syntax on PKM buffers.
---@return nil
function M.deactivate()
  _active = false

  local views = require('pkm.views')
  local ui    = require('pkm.ui')

  -- open_sidebar() with no name closes the sidebar if open; no-op otherwise.
  if views.is_sidebar_open() then views.open_sidebar() end
  if ui.is_bufpanel_open()   then ui.toggle_bufpanel() end

  syntax_disable_all()

  vim.notify('[pkm] PKM mode off', vim.log.levels.INFO)
end

--- Toggle PKM mode: activate if inactive, deactivate if active.
---@return nil
function M.toggle()
  if _active then M.deactivate() else M.activate() end
end

--- Set mode to a specific state by name.
---@param state string  'on' to activate, 'off' to deactivate; any other value toggles
---@return nil
function M.set(state)
  if     state == 'on'  then M.activate()
  elseif state == 'off' then M.deactivate()
  else                       M.toggle()
  end
end

--- Return true if PKM mode is currently active.
---@return boolean
function M.is_active()
  return _active
end

return M
