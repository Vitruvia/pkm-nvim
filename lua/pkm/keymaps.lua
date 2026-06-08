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
  map(k.search, "<cmd>PKMSearch<cr>", "Search Content")
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
  map(k.browse, "<cmd>PKMBrowse<cr>", "Browse Notes")

  -- --------------------------------------------------------------------------
  -- KEYMAPS: views
  -- -------------------------------------------------------------------------- 
  map(k.view_last,    "<cmd>PKMViewLast<cr>",    "Last View")
  map(k.view_sidebar, "<cmd>PKMViewSidebar<cr>", "View Sidebar")
  map(k.view_list, "<cmd>PKMViews<cr>", "List Views")
  map(k.view_buffers, "<cmd>PKMBuffers<cr>", "Buffer Panel")

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
  -- Emphasis wrapping
  local function map_emphasis(lhs, marker)
    if not lhs then return end
    vim.keymap.set('n', lhs,
      function() return require('pkm.markdown').wrap_with_marker(marker) end,
      { expr = true, desc = 'PKM: wrap ' .. marker .. ' (motion)', silent = true })
    vim.keymap.set('v', lhs,
      function() require('pkm.markdown')._wrap_visual(marker) end,
      { desc = 'PKM: wrap ' .. marker .. ' (selection)', silent = true })
  end

  map_emphasis(k.wrap_italic,      '*')
  map_emphasis(k.wrap_bold,        '**')
  map_emphasis(k.wrap_bold_italic, '***')
  map_emphasis(k.wrap_code,        '`')
  map_emphasis(k.wrap_strike,      '~~')
end

return M
