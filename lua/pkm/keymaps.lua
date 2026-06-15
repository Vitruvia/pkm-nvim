-- =============================================================================
-- pkm.keymaps — Keymap registration
-- =============================================================================
-- Dependencies : none (all modules required lazily via commands)
-- Consumed by  : pkm.init (called once during setup)
--
-- NOTE: register(config) must receive the resolved config table because
-- keymap lhs strings are needed immediately at registration time.
--
-- Public API:
--   register(config) → Register all <leader> keymaps from config.keymaps
-- =============================================================================
local M = {}

-- =============================================================================
-- SECTION: Registration
-- =============================================================================
--- Register all PKM keymaps using lhs strings from config.keymaps.
--- Silently skips any keymap whose lhs is nil or false.
---@param config table Resolved PKM config (needs config.keymaps)
function M.register(config)
  local k = config.keymaps

  -- --------------------------------------------------------------------------
  -- KEYMAPS: note operations
  -- --------------------------------------------------------------------------
  local function map(lhs, cmd, desc)
    if lhs then vim.keymap.set('n', lhs, cmd, { desc = "PKM: " .. desc, silent = true }) end
  end

  if config.keymaps.promote_note then
    vim.keymap.set('n', config.keymaps.promote_note,
      function() require('pkm.notes').promote_note() end,
      { noremap = true, silent = true, desc = "PKM: Promote note" })
  end

  map(k.new_note, "<cmd>PKMNewNote<cr>", "New Note")
  map(k.new_journal, "<cmd>PKMNewJournal<cr>", "New Journal")
  map(k.new_scratchpad, "<cmd>PKMNewScratchpad<cr>", "New Scratchpad")
  map(k.delete_note, "<cmd>PKMDeleteNote<cr>", "Delete Note")
  map(k.browse, "<cmd>PKMBrowse<cr>", "Browse Notes")
  map(k.browse_tags, "<cmd>PKMTags<cr>", "Browse Tags") 
  map(k.insert_citation, "<cmd>PKMInsertCitation<cr>", "Insert Citation")
  map(k.goto_citation, "<cmd>PKMGotoCitation<cr>", "Goto Citation")
  map(k.link_note, "<cmd>PKMLinkNote<cr>", "Link Note")
  map(k.follow_link, "<cmd>PKMFollowLink<cr>", "Follow Link")
  map(k.backlinks, "<cmd>PKMBacklinks<cr>", "Backlinks")
  map(k.import_note, "<cmd>PKMImport<cr>", "Import Note")
  map(k.convert_note, "<cmd>PKMConvertNote<cr>", "Convert Note")
  map(k.transpose_note, "<cmd>PKMTranspose<cr>", "Transpose Note")
  map(k.change_note_type, "<cmd>PKMChangeType<cr>", "Change Note Type")
  map(k.rename_note, "<cmd>PKMRenameNote<cr>", "Rename Note")
  map(k.set_title,  "<cmd>PKMSetTitle<cr>",  "Set Title")
  map(k.add_tag,    "<cmd>PKMAddTag<cr>",    "Add Tag")
  map(k.remove_tag, "<cmd>PKMRemoveTag<cr>", "Remove Tag")

  -- --------------------------------------------------------------------------
  -- KEYMAPS: views
  -- -------------------------------------------------------------------------- 
  map(k.view_last,    "<cmd>PKMViewLast<cr>",    "Last View")
  map(k.view_sidebar, "<cmd>PKMViewSidebar<cr>", "View Sidebar")
  map(k.view_list, "<cmd>PKMViews<cr>", "List Views")
  map(k.view_buffers, "<cmd>PKMBuffers<cr>", "Buffer Panel")

  if k.focus_sidebar then
    vim.keymap.set('n', k.focus_sidebar, function()
      local win = require('pkm.views').get_sidebar_win()
      if win then
        vim.api.nvim_set_current_win(win)
      else
        vim.notify('[pkm] sidebar is not open', vim.log.levels.INFO)
      end
    end, { desc = 'PKM: focus sidebar', silent = true })
  end

  if k.toggle_mode then
    vim.keymap.set('n', k.toggle_mode, '<cmd>PKMMode<cr>',
      { desc = 'PKM: toggle PKM mode', silent = true })
  end

  if k.toggle_file_explorer then
    vim.keymap.set('n', k.toggle_file_explorer, function()
      local views   = require('pkm.views')
      local cfg     = require('pkm').config
      local width   = cfg.sidebar_width or 40
      local pkm_dir = vim.fn.fnameescape(cfg.root_path)

      -- Detect any open netrw window in the current tabpage.
      local netrw_win = nil
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == '' then
          if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'netrw' then
            netrw_win = win; break
          end
        end
      end

      if views.is_sidebar_open() then
        -- PKM sidebar → close it, open netrw at the same width on the left.
        views.open_sidebar()   -- no-arg call toggles closed
        vim.cmd(string.format('topleft %dvsplit %s', width, pkm_dir))
      elseif netrw_win then
        -- Netrw open → close it, restore the PKM sidebar.
        vim.api.nvim_win_close(netrw_win, false)
        views.open_sidebar()
      else
        -- Neither open → open PKM sidebar (default).
        views.open_sidebar()
      end
    end, { desc = 'PKM: toggle netrw file explorer / views sidebar', silent = true })
  end

  -- Netrw quality-of-life: winbar shows current directory; window
  -- navigation keymaps override netrw's <C-l> capture.
  local netrw_aug = vim.api.nvim_create_augroup('PKMNetrwFixes', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group   = netrw_aug,
    pattern = 'netrw',
    callback = function(ev)
      local function update_winbar()
        local dir = vim.b[ev.buf].netrw_curdir
                 or vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ev.buf), ':p:h')
        -- Display path relative to home (~) to reduce width.
        dir = vim.fn.fnamemodify(dir, ':~'):gsub('\\', '/')
        local win = vim.fn.bufwinid(ev.buf)
        if win ~= -1 then
          vim.api.nvim_set_option_value('winbar', ' ' .. dir, { win = win })
        end
      end

      vim.schedule(update_winbar)  -- defer so b:netrw_curdir is populated

      vim.api.nvim_create_autocmd('BufEnter', {
        buffer   = ev.buf,
        callback = update_winbar,
      })

      -- Window navigation (see Item 2).
      local ko = { noremap = true, silent = true, buffer = ev.buf }
      vim.keymap.set('n', '<C-h>', '<C-w>h', ko)
      vim.keymap.set('n', '<C-j>', '<C-w>j', ko)
      vim.keymap.set('n', '<C-k>', '<C-w>k', ko)
      vim.keymap.set('n', '<C-l>', '<C-w>l', ko)
    end,
  })

  -- --------------------------------------------------------------------------
  -- KEYMAPS: markdown editing
  -- -------------------------------------------------------------------------- 
  
  -- Header Editing
  map(k.next_header, "<cmd>PKMNextHeader<cr>", "Next Header (increment counter)")

  if k.header_level_up then
    vim.keymap.set('n', k.header_level_up, '<cmd>PKMHeaderLevelUp<cr>',
      { desc = "PKM: Header Level Up (buffer)", silent = true })
    vim.keymap.set('v', k.header_level_up, ':PKMHeaderLevelUp<cr>',
      { desc = "PKM: Header Level Up (selection)", silent = true })
  end

  if k.header_level_down then
    vim.keymap.set('n', k.header_level_down, '<cmd>PKMHeaderLevelDown<cr>',
      { desc = "PKM: Header Level Down (buffer)", silent = true })
    vim.keymap.set('v', k.header_level_down, ':PKMHeaderLevelDown<cr>',
      { desc = "PKM: Header Level Down (selection)", silent = true })
  end

  if k.renumber_list then
    vim.keymap.set('n', k.renumber_list, '<cmd>PKMRenumberList<cr>',
      { desc = 'PKM: Renumber sequence (paragraph)', silent = true })
    vim.keymap.set('v', k.renumber_list, ':PKMRenumberList<cr>',
      { desc = 'PKM: Renumber sequence (selection)', silent = true })
  end

  if k.convert_list then
    vim.keymap.set('n', k.convert_list, '<cmd>PKMConvertList<cr>',
      { desc = 'PKM: Convert list ordered/unordered (paragraph)', silent = true })
    vim.keymap.set('v', k.convert_list, ':PKMConvertList<cr>',
      { desc = 'PKM: Convert list ordered/unordered (selection)', silent = true })
  end
end

return M
