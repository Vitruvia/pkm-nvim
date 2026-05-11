-- =============================================================================
-- pkm.keymaps — Keymap registration
-- =============================================================================
-- Dependencies : none (all modules required lazily via commands)
-- Consumed by  : pkm.init (called once during setup)
--
-- NOTE: register(config) must receive the resolved config table because
-- keymap lhs strings are needed immediately at registration time.
--
-- Known issue: quick_capture maps to PKMNewNote instead of a dedicated
-- PKMQuickCapture command. See dead code / known bugs list.
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

  --- KEYMAPS ---
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
  map(k.quick_capture, "<cmd>PKMNewNote<cr>", "Quick Capture")
  map(k.import_note, "<cmd>PKMImport<cr>", "Import Note")
  map(k.convert_note, "<cmd>PKMConvertNote<cr>", "Convert Note")
  map(k.transpose_note, "<cmd>PKMTranspose<cr>", "Transpose Note")
end

return M
