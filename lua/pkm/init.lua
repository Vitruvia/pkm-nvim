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

-- Notes saved at least once since they were opened: bufnr → true.
-- `last_updated_on` is stamped onto the *file* when such a buffer is released
-- (see stamp_on_release), never into the buffer while it is being edited —
-- writing it during the write cycle is what dragged `u` into the frontmatter.
-- The flag is what keeps a note that was merely opened and closed untouched.
local _saved_since_open = {}

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

--- Is this path a note inside the PKM root?
---@param filepath string
---@return boolean
local function in_root(filepath)
  if not filepath or filepath == '' then return false end
  local norm_path = filepath:gsub('\\', '/')
  local norm_root = (M.config.root_path or ''):gsub('\\', '/')
  if norm_root == '' then return false end
  return norm_path:lower():find(norm_root:lower(), 1, true) ~= nil
end

--- Does the buffer's content differ from these lines?
--- Cheap enough to run on every save: it stops at the first difference, and
--- the common case (identical) is one pass over lines already in memory.
---@param bufnr integer
---@param lines string[]
---@return boolean
local function differs(bufnr, lines)
  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #buf_lines ~= #lines then return true end
  for i = 1, #lines do
    if buf_lines[i] ~= lines[i] then return true end
  end
  return false
end

--- Write `last_updated_on` into the note **on disk**, for a buffer that is
--- being released.
---
--- This is where the field is maintained, and the timing is the whole point.
--- Writing it during the write cycle — as `BufWritePre` used to — puts the
--- frontmatter rewrite in the same undo block as the user's edit, and Neovim
--- positions the cursor after `u` on the *first changed line of the block*.
--- The frontmatter sits above the body, so `u` always landed there. No amount
--- of saving and restoring the cursor changes that: the position is recomputed
--- from the changed region, which is why three previous attempts at this bug
--- failed. The only fix is not to touch the buffer while it is being edited.
---
--- The buffer is on its way out, so writing the file behind it cannot
--- desynchronise anything the user is looking at, and nothing in the plugin
--- reads this field — recency comes from the filesystem mtime the index
--- already stores.
---@param bufnr integer
local function stamp_on_release(bufnr)
  if not _saved_since_open[bufnr] then return end
  _saved_since_open[bufnr] = nil

  local ok, filepath = pcall(vim.api.nvim_buf_get_name, bufnr)
  if not ok or not in_root(filepath) or not filepath:match('%.md$') then return end
  if vim.fn.filereadable(filepath) ~= 1 then return end   -- trashed or renamed

  local lines_ok, lines = pcall(vim.fn.readfile, filepath)
  if not lines_ok or not lines or lines[1] ~= '---' then return end

  local yaml_m = require('pkm.yaml')
  local frontmatter, content_start = yaml_m.parse_frontmatter(lines)
  if not frontmatter then return end
  if frontmatter.cites and type(frontmatter.cites) ~= 'table' then return end

  frontmatter.last_updated_on = require('pkm.timestamp').to_iso8601()
  pcall(yaml_m.save_frontmatter, frontmatter, content_start, filepath)
  pcall(function() require('pkm.index').invalidate(filepath) end)
end

--- Register BufWritePost and BufReadPost autocmds for the PKMSync augroup.
--- BufWritePost: syncs journal filename to created_on, updates citations.
--- BufDelete/VimLeavePre: stamps last_updated_on onto released notes.
--- BufReadPost: registers buffer-local symbol abbreviations for PKM notes.
--- Only fires for .md files within M.config.root_path.
function M.setup_sync_autocmds()
  local augroup = vim.api.nvim_create_augroup("PKMSync", { clear = true })

  -- Before the write: capture fold state, and remember that this note was
  -- saved. The frontmatter is deliberately NOT touched here — see
  -- stamp_on_release() for where `last_updated_on` is written and why.
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = augroup, pattern = "*.md",
    callback = function()
      local filepath = vim.fn.expand("%:p")
      local norm_path = filepath:gsub("\\", "/")
      local norm_root = M.config.root_path:gsub("\\", "/")
      if not norm_path:lower():find(norm_root:lower(), 1, true) then return end

      local pre_buf = vim.api.nvim_get_current_buf()
      _saved_since_open[pre_buf] = true

      -- Capture fold states before any buffer modification so BufWritePost can
      -- restore them even if sync parser:parse() or noautocmd e closes them.
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
    end,
  })

  -- The note is leaving: stamp it now, when no undo history is at stake.
  -- BufDelete rather than BufUnload, because `:edit` unloads and reloads a
  -- buffer that is not going anywhere, and stamping there would write the file
  -- underneath a reload already in progress.
  vim.api.nvim_create_autocmd('BufDelete', {
    group = augroup, pattern = '*.md',
    callback = function(ev) stamp_on_release(ev.buf) end,
  })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = augroup,
    callback = function()
      for bufnr in pairs(_saved_since_open) do
        if vim.api.nvim_buf_is_valid(bufnr) then stamp_on_release(bufnr) end
      end
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
            -- Replace the buffer only when the file actually differs. The
            -- reload exists for what update_references wrote into *this* note;
            -- when nothing wrote, replacing the buffer with its own content
            -- still costs an undo entry, and an undo entry is what drags `u`
            -- off the user's edit.
            if differs(written_buf, reload_lines) then
              pcall(vim.api.nvim_buf_set_lines, written_buf, 0, -1, false, reload_lines)
              -- `:undojoin` is deliberately absent: this change is the
              -- plugin's, not the user's, and merging it into their block is
              -- the defect this phase exists to remove.
              --
              -- Seal it as its own undo block. A buffer mutation made from a
              -- scheduled callback leaves the block *open* — Neovim closes one
              -- when a command finishes in the main loop, and there is no
              -- command here — so without this the next thing the user types is
              -- absorbed into the reload's state, and a single `u` reverts
              -- their edit and the reload together, landing on line 1.
              -- `let &ul = &ul` is the documented way to force the break;
              -- setting undolevels to -1 and back is *not* the same thing, it
              -- discards the history entirely.
              pcall(vim.cmd, 'let &undolevels = &undolevels')
            end

            -- Write the buffer back even when nothing differed. The citation
            -- passes above touch the file on disk after Neovim's own write,
            -- which leaves Neovim's record of this file stale — and a stale
            -- record makes a later `:w` stop with W11 ("changed since editing
            -- started, really write?") on a note nothing else edited. Folding
            -- this into the branch above is exactly what made repeated saves
            -- start prompting.
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
