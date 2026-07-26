-- =============================================================================
-- pkm.bufsync — Keeping open buffers honest across bulk disk writes
-- =============================================================================
-- Dependencies : pkm.utils
-- Consumed by  : pkm.rename (title batches), pkm.tags (tag batches)
--
-- A bulk operation writes note files directly. Any of those notes may also be
-- open in a window, which creates exactly two problems worth solving:
--
--   * an **unmodified** buffer keeps showing the old text until something makes
--     it re-read the file — so it is reloaded, silently, right after the write;
--   * a **modified** buffer holds edits the write knows nothing about. Saving it
--     later would quietly undo what the batch just did, so the user is asked
--     first — and only then, because a prompt nobody needed is friction.
--
-- Nothing here decides *whether* to write; it only keeps what is on screen in
-- agreement with what is on disk.
--
-- Public API:
--   buffer_for(path)      → bufnr of a loaded buffer holding path, or nil
--   unsaved(paths)        → the subset open with unsaved changes
--   save(paths)           → write those buffers
--   reload(paths)         → re-read unmodified buffers from disk
--   guard(paths, on_ready) → ask about unsaved buffers, then continue
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: Lookup
-- =============================================================================

--- The loaded buffer holding this file, if there is one.
--- Paths are compared normalised, so a buffer opened as `P:/notes/x.md` is found
--- from `P:\notes\x.md`.
---@param path string
---@return integer|nil bufnr
function M.buffer_for(path)
  local target = utils.normalize(path):lower()

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= '' and utils.normalize(name):lower() == target then
        return bufnr
      end
    end
  end

  return nil
end

--- Which of these notes are open with unsaved changes.
---@param paths string[]
---@return string[] paths
---@return integer[] bufnrs  Parallel to the returned paths
function M.unsaved(paths)
  local out, bufs = {}, {}

  for _, path in ipairs(paths or {}) do
    local bufnr = M.buffer_for(path)
    if bufnr and vim.bo[bufnr].modified then
      out[#out + 1]  = path
      bufs[#bufs + 1] = bufnr
    end
  end

  return out, bufs
end

-- =============================================================================
-- SECTION: Writes and reloads
-- =============================================================================

--- Write the buffers holding these notes, if they are modified.
---@param paths string[]
---@return integer written
function M.save(paths)
  local written = 0

  for _, path in ipairs(paths or {}) do
    local bufnr = M.buffer_for(path)
    if bufnr and vim.bo[bufnr].modified then
      vim.api.nvim_buf_call(bufnr, function() vim.cmd('silent! write') end)
      written = written + 1
    end
  end

  return written
end

--- Re-read the buffers holding these notes from disk.
--- Modified buffers are left alone: reloading one would throw away edits the
--- user has not saved, which no bulk operation is entitled to do.
---
--- The frontmatter fold is rebuilt afterwards. It is `foldmethod=manual`, so it
--- does not survive a reload at all, and a batch that adds a tag changes the
--- frontmatter's line count — which is how the bottom of the block ended up
--- outside its own fold until the next save happened to rebuild it.
---@param paths string[]
---@return integer reloaded
function M.reload(paths)
  local reloaded = 0

  for _, path in ipairs(paths or {}) do
    local bufnr = M.buffer_for(path)
    if bufnr and not vim.bo[bufnr].modified then
      vim.api.nvim_buf_call(bufnr, function() vim.cmd('silent! edit!') end)
      pcall(function() require('pkm.syntax').refresh_fold(bufnr) end)
      reloaded = reloaded + 1
    end
  end

  return reloaded
end

-- =============================================================================
-- SECTION: The gate
-- =============================================================================

--- Ask about unsaved buffers, then hand control back.
--- **Only** asks when at least one of the notes is open with unsaved changes —
--- the common case reaches on_ready with no prompt at all.
---
--- Answering yes writes those buffers first, so the batch reads and rewrites
--- the text the user actually has. Answering no proceeds anyway: the write still
--- happens, but those buffers are not reloaded afterwards, and saving one later
--- will overwrite what the batch wrote — which is said out loud rather than
--- discovered.
---@param paths    string[]
---@param on_ready function(paths: string[])
function M.guard(paths, on_ready)
  local dirty = M.unsaved(paths)
  if #dirty == 0 then
    on_ready(paths)
    return
  end

  -- Typeahead left over from the panel that got here — the `<CR>` that
  -- confirmed it, above all — would answer this dialog before it is on screen,
  -- and the user would never see it. inputsave() parks pending input first.
  vim.fn.inputsave()
  local answer = vim.fn.confirm(
    string.format('%d selected note%s open with unsaved changes. Save first?',
      #dirty, #dirty == 1 and ' is' or 's are'),
    '&yes\n&no', 1)
  vim.fn.inputrestore()

  if answer == 1 then
    M.save(dirty)
  elseif answer == 2 then
    vim.notify(
      string.format('[pkm] %d buffer%s left unsaved — saving %s later will '
        .. 'overwrite this change', #dirty, #dirty == 1 and '' or 's',
        #dirty == 1 and 'it' or 'them'),
      vim.log.levels.WARN)
  else
    return   -- dialog dismissed: the batch does not run
  end

  on_ready(paths)
end

return M
