-- =============================================================================
-- pkm.init — Plugin entry point and orchestration
-- =============================================================================
-- Dependencies : pkm.config, pkm.utils, and all other pkm.* modules
-- Consumed by  : Neovim (via plugin/pkm.lua autoload marker)
--                pkm.commands (via require('pkm') for delete and sync)
--
-- This module's only responsibilities are:
--   1. Resolve config and call setup() on every module
--   2. Register commands and keymaps
--   3. Register sync autocmds
--   4. Hold delete_note_safely() and setup_sync_autocmds() which need
--      direct access to M.config
--
-- Public API:
--   setup(user_config)         → Initialize the entire plugin
--   setup_sync_autocmds()      → Register BufWritePost and BufReadPost autocmds
--   delete_note_safely()       → Confirm, cleanup citations, delete current note
--   M.config                   → Resolved config table (set by setup())
-- =============================================================================
local M = {}

-- Pre-write fold state: bufnr → {win_id → was_open (boolean)}
-- Populated by BufWritePre before any buffer modification; consumed by BufWritePost.
local _pre_write_fold_states = {}

-- =============================================================================
-- SECTION: Setup
-- =============================================================================
--- Initialize the PKM plugin. Resolves config, calls setup() on all modules,
--- registers commands and keymaps, and sets up sync autocmds if enabled.
--- Must be called once from the user's lazy.nvim config function.
---@param user_config table|nil User config table; merged over defaults by pkm.config.resolve()
function M.setup(user_config)
  M.config = require('pkm.config').resolve(user_config)

  -- Initialize Modules
  require('pkm.timestamp').setup(M.config)
  require('pkm.yaml').setup(M.config)
  require('pkm.citations').setup(M.config)
  require('pkm.templates').setup(M.config)
  require('pkm.journal').setup(M.config)
  require('pkm.notes').setup(M.config)
  require('pkm.ui').setup(M.config)
  require('pkm.trash').setup(M.config)

  -- Wire commands and keymaps
  require('pkm.commands').register()
  require('pkm.keymaps').register(M.config)
  if M.config.sync.enabled then M.setup_sync_autocmds() end

  -- Activate index
  require('pkm.index').setup(M.config)
  require('pkm.mode').setup(M.config)
  require('pkm.views').setup()

end 

-- =============================================================================
-- SECTION: Sync autocmds
-- =============================================================================
--- Register BufWritePost and BufReadPost autocmds for the PKMSync augroup.
--- BufWritePost: updates last_updated_on, syncs journal filename to created_on, updates citations.
--- BufReadPost: registers buffer-local symbol abbreviations for PKM notes.
--- Only fires for .md files within M.config.root_path.
function M.setup_sync_autocmds()
  local augroup = vim.api.nvim_create_augroup("PKMSync", { clear = true })

  -- Update last_updated_on in the buffer before the write.
  -- Neovim then writes the updated buffer to disk in the normal save cycle.
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      local norm_path = filepath:gsub("\\", "/")
      local norm_root = M.config.root_path:gsub("\\", "/")
      if not norm_path:lower():find(norm_root:lower(), 1, true) then return end

      -- Capture fold states before any buffer modification so BufWritePost can
      -- restore them even if sync parser:parse() or noautocmd e closes them.
      local pre_buf = vim.api.nvim_get_current_buf()
      if require('pkm.mode').is_active() then
        local fold_capture = {}
        for _, win in ipairs(vim.fn.win_findbuf(pre_buf)) do
          if vim.api.nvim_win_get_config(win).relative == '' then
            fold_capture[win] = vim.api.nvim_win_call(win,
              function() return vim.fn.foldclosed(1) == -1 end)
          end
        end
        _pre_write_fold_states[pre_buf] = fold_capture
      end
    
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      if not lines or lines[1] ~= "---" then return end

      local yaml_m      = require('pkm.yaml')
      local timestamp_m = require('pkm.timestamp')
      local frontmatter, content_start = yaml_m.parse_frontmatter(lines)
      if not frontmatter then return end
      if frontmatter.cites and type(frontmatter.cites) ~= "table" then return end

      frontmatter.last_updated_on = timestamp_m.to_iso8601()
      -- Merge into the same undo block as the user's last edit so `u` doesn't
      -- need an extra press to reach it. pcall guards E790 (undojoin not allowed
      -- right after undo/redo) and the case where there's no prior change to
      -- join (e.g. :w immediately after opening the file, no edits yet).
      pcall(vim.cmd, 'undojoin')
      yaml_m.save_frontmatter(frontmatter, content_start)  -- Case A: buffer update, no disk write
    end,
  })

  -- After write: sync journal filename, update citations, reload buffer silently.
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup, pattern = "*.md",
    callback = function(ev)
      local written_buf = ev.buf   -- capture now; current buffer may change before schedule runs
      vim.schedule(function()
        -- Guard: buffer may have been deleted between the write and this
        -- callback (e.g. bdelete immediately after w in the buffer panel).
        if not vim.api.nvim_buf_is_valid(written_buf) then return end
        local filepath = vim.api.nvim_buf_get_name(written_buf)
        if filepath == '' then return end

        local root      = M.config.root_path
        local norm_path = filepath:gsub("\\", "/")
        local norm_root = root:gsub("\\", "/")
        if not norm_path:lower():find(norm_root:lower(), 1, true) then return end

        local yaml      = require('pkm.yaml')
        local journal   = require('pkm.journal')
        local citations = require('pkm.citations')

        -- last_updated_on is already written by BufWritePre above.
        local disk_lines = vim.fn.readfile(filepath)
        if disk_lines[1] == "---" then
          local frontmatter, _ = yaml.parse_frontmatter(disk_lines)
          if not frontmatter or (frontmatter.cites and type(frontmatter.cites) ~= "table") then
            vim.notify("PKM Error: Frontmatter corrupted. Sync aborted.", vim.log.levels.ERROR)
            return
          end
        end

        if filepath:find(M.config.folders.journal, 1, true) then
          journal.sync_filename_on_save()
        end

        if M.config.sync.auto_sync_on_save then
          citations.update_references(filepath)
        end

        citations.propagate_title(filepath)

        -- Silently reload the WRITTEN buffer (not whichever buffer is
        -- current now) to reflect changes made by update_references.
        -- nvim_buf_call ensures noautocmd e targets the correct buffer even
        -- when the current window changed since the write (e.g. after bdelete
        -- in the panel). Second validity check covers bdelete during sync.
        if not vim.api.nvim_buf_is_valid(written_buf) then return end
        vim.api.nvim_buf_call(written_buf, function()
          local view = vim.fn.winsaveview()
          local ok_read, reload_lines = pcall(vim.fn.readfile, filepath)
          if ok_read then
            pcall(vim.cmd, 'undojoin')
            pcall(vim.api.nvim_buf_set_lines, written_buf, 0, -1, false, reload_lines)
            pcall(vim.cmd, 'noautocmd write!')
          end
          vim.fn.winrestview(view)
          -- noautocmd e is no longer used, so there's no modeline-scan risk
          -- to guard against — this Syntax refire is now a no-op, kept as-is.
          vim.cmd('doautocmd Syntax')
          -- Restart PKM tree-sitter if active; harmless no-op now that the
          -- highlighter is never actually stopped by the reload above.
          if require('pkm.mode').is_active() then
            -- Save per-window frontmatter fold state before TS restart.
            -- foldclosed(1) == -1 means line 1 (opening ---) is in an open fold.
            -- Use pre-write states saved in BufWritePre (before buffer modification).
            -- Falls back to current state if PKM mode was inactive at write time.
            local fold_states = _pre_write_fold_states[written_buf]
            _pre_write_fold_states[written_buf] = nil
            if not fold_states then
              fold_states = {}
              for _, win in ipairs(vim.api.nvim_list_wins()) do
                if vim.api.nvim_win_get_buf(win) == written_buf
                and vim.api.nvim_win_get_config(win).relative == '' then
                  fold_states[win] = vim.api.nvim_win_call(win,
                    function() return vim.fn.foldclosed(1) == -1 end)
                end
              end
            end
            pcall(vim.treesitter.start, written_buf, 'markdown')

            -- Rebuild the frontmatter fold: foldmethod=manual folds do not
            -- survive noautocmd e (unlike the old foldexpr system this
            -- restore logic predates) — zR alone has nothing to reopen.
            -- Rebuild via pkm.syntax first, then reopen per window only
            -- where it was open before the write.
            vim.schedule(function()
              if not vim.api.nvim_buf_is_valid(written_buf) then return end
              require('pkm.syntax').refresh_fold(written_buf)
              for win, was_open in pairs(fold_states) do
                if vim.api.nvim_win_is_valid(win) and was_open then
                  vim.api.nvim_win_call(win, function()
                    vim.cmd('silent! normal! zR')
                  end)
                end
              end
            end)
          end
        end)
        -- Index was already re-read synchronously; refresh sidebar so
        -- tag/title/view-membership changes appear immediately.
        require('pkm.views').refresh_sidebar_if_open()
      end)   
    end,
  })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      local root = M.config.root_path
      local norm_path = filepath:gsub("\\", "/")
      local norm_root = root:gsub("\\", "/")
      if not norm_path:lower():find(norm_root:lower(), 1, true) then return end
      require('pkm.markdown').setup_symbols(M.config.symbols)
    end,
  })
end

-- =============================================================================
-- SECTION: Note deletion
-- =============================================================================

--- Switch every non-float window in the current tabpage that is showing
--- `bufnr` to its alternate buffer, another listed buffer, or a new empty
--- buffer. Mirrors the detach_buf_from_wins helper in ui.lua; applied here
--- before bdelete! to prevent the window layout from collapsing.
local function _detach_buf_from_wins(bufnr)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == ''
    and vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_win_call(win, function()
        local alt = vim.fn.bufnr('#')
        if alt > 0 and alt ~= bufnr
        and vim.api.nvim_buf_is_valid(alt)
        and vim.bo[alt].buflisted then
          vim.cmd('noautocmd buffer ' .. alt)
          return
        end
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if b ~= bufnr
          and vim.api.nvim_buf_is_valid(b)
          and vim.bo[b].buflisted
          and vim.api.nvim_buf_get_name(b) ~= '' then
            vim.cmd('noautocmd buffer ' .. b)
            return
          end
        end
        vim.cmd('noautocmd enew')
        vim.bo.bufhidden = 'wipe'
      end)
    end
  end
end

--- Delete or trash the current note.
--- With trash.enabled = true (default): moves to .pkm-trash/ and preserves
--- backlinks; use :PKMRestoreNote to undo or :PKMEmptyTrash to permanently
--- delete. With trash.enabled = false: permanent delete (strips backlinks).
function M.delete_note_safely()
  local filepath = vim.fn.expand('%:p')
  local root     = M.config.root_path

  local norm_path = filepath:gsub('\\', '/')
  local norm_root = root:gsub('\\', '/')
  if filepath == '' or not norm_path:lower():find(norm_root:lower(), 1, true) then
    vim.notify('Not a valid PKM note.', vim.log.levels.ERROR)
    return
  end

  local trash_enabled = M.config.trash and M.config.trash.enabled
  local filename      = vim.fn.fnamemodify(filepath, ':t')
  local action_note   = trash_enabled
    and '(moves to trash · :PKMRestoreNote to undo)'
    or  '(permanent · cannot be undone)'

  vim.fn.inputsave()
  local confirm = vim.fn.input(
    string.format("Delete '%s'? %s\n(yes/no): ", filename, action_note))
  vim.fn.inputrestore()

  if confirm:lower() ~= 'yes' then
    vim.notify('Deletion cancelled.', vim.log.levels.INFO)
    return
  end

  -- Detach the buffer from all windows before deletion so the layout
  -- is never disrupted (same pattern as ui.lua's detach_buf_from_wins).
  local bufnr = vim.fn.bufnr('%')
  _detach_buf_from_wins(bufnr)

  if trash_enabled then
    vim.cmd('bdelete! ' .. bufnr)
    local trash = require('pkm.trash')
    if trash.trash_note(filepath) then
      require('pkm.index').invalidate(filepath)
      require('pkm.views').refresh_sidebar_if_open()
      vim.notify(
        string.format("'%s' moved to trash. Use :PKMRestoreNote to undo.", filename),
        vim.log.levels.INFO)
    else
      vim.notify('Failed to move note to trash.', vim.log.levels.ERROR)
    end
  else
    require('pkm.citations').cleanup_deleted_note(filepath)
    vim.cmd('bdelete! ' .. bufnr)
    if vim.fn.delete(filepath) == 0 then
      require('pkm.index').invalidate(filepath)
      require('pkm.views').refresh_sidebar_if_open()
      vim.notify('Note permanently deleted.', vim.log.levels.INFO)
    else
      vim.notify('Failed to delete file.', vim.log.levels.ERROR)
    end
  end
end

return M
