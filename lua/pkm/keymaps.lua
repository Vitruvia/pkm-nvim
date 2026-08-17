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

  map(k.new_note, "<cmd>PKMNote new<cr>", "New Note")
  map(k.new_relative, "<cmd>PKMNote relative<cr>", "New Relative Note")
  map(k.new_journal, "<cmd>PKMNote journal<cr>", "New Journal")
  map(k.new_scratchpad, "<cmd>PKMNote scratch<cr>", "New Scratchpad")
  map(k.delete_note, "<cmd>PKMNote delete<cr>", "Delete Note")
  map(k.browse, "<cmd>PKMBrowse<cr>", "Browse Notes")
  map(k.browse_tags, "<cmd>PKMBrowse tags<cr>", "Browse Tags")
  map(k.insert_citation, "<cmd>PKMCite insert<cr>", "Insert Citation")
  map(k.goto_citation, "<cmd>PKMCite goto<cr>", "Goto Citation")
  map(k.link_note, "<cmd>PKMCite link<cr>", "Link Note")
  map(k.follow_link, "<cmd>PKMCite follow<cr>", "Follow Link")
  map(k.backlinks, "<cmd>PKMCite backlinks<cr>", "Backlinks")
  map(k.import_note, "<cmd>PKMNote import<cr>", "Import Note")
  map(k.convert_note, "<cmd>PKMNote convert<cr>", "Convert Note")
  map(k.transpose_note, "<cmd>PKMNote transpose<cr>", "Transpose Note")
  map(k.change_note_type, "<cmd>PKMNote changetype<cr>", "Change Note Type")
  map(k.rename_note, "<cmd>PKMNote rename<cr>", "Rename Note")
  map(k.set_title,  "<cmd>PKMNote settitle<cr>",  "Set Title")
  map(k.add_tag,    "<cmd>PKMTag add<cr>",    "Add Tag")
  map(k.remove_tag, "<cmd>PKMTag remove<cr>", "Remove Tag")

  -- --------------------------------------------------------------------------
  -- KEYMAPS: views
  -- --------------------------------------------------------------------------
  map(k.view_last,    "<cmd>PKMBrowse views last<cr>", "Last View")
  map(k.view_sidebar, "<cmd>PKMPanel sidebar<cr>",     "View Sidebar")
  map(k.view_list,    "<cmd>PKMBrowse views<cr>",      "List Views")
  map(k.view_buffers, "<cmd>PKMPanel buffers<cr>", "Buffer Panel")
  map(k.nav_panel,    "<cmd>PKMPanel nav<cr>",     "File Navigation (headings)")
  map(k.explorer,     "<cmd>PKMPanel explorer<cr>", "Explorer (sidebar + buffers)")

  -- Cycle focus among open panes (+ a home editing window). <C-Tab> forward,
  -- <C-S-Tab> back; leaves the user's own <C-hjkl>/<C-s>/<C-x> window scheme
  -- untouched. See pkm.panel.cycle_focus.
  if k.cycle_panes then
    vim.keymap.set('n', k.cycle_panes, function()
      require('pkm.panel').cycle_focus(1)
    end, { desc = 'PKM: cycle panes (forward)', silent = true })
  end
  if k.cycle_panes_back then
    vim.keymap.set('n', k.cycle_panes_back, function()
      require('pkm.panel').cycle_focus(-1)
    end, { desc = 'PKM: cycle panes (backward)', silent = true })
  end

  if k.nav_search then
    vim.keymap.set('n', k.nav_search, function()
      require('pkm.popup').open('nav')   -- cyclable pop-up; <C-l> → views → browse
    end, { desc = 'PKM: heading pop-up (cyclable panel)', silent = true })
  end

  if k.nav_search_resume then
    vim.keymap.set('n', k.nav_search_resume, function()
      require('pkm.popup').resume()      -- reopen the previous pop-up search (Item 10)
    end, { desc = 'PKM: resume last pop-up search', silent = true })
  end

  if k.view_panel then
    require('pkm.views').set_panel_keymap(k.view_panel)
  end

  if k.focus_sidebar then
    vim.keymap.set('n', k.focus_sidebar, function()
      require('pkm.views').focus_sidebar()
    end, { desc = 'PKM: focus sidebar (toggle in/out)', silent = true })
  end

  if k.toggle_mode then
    vim.keymap.set('n', k.toggle_mode, '<cmd>PKMPanel mode<cr>',
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
      -- Guard: netrw's initial listing appears to populate a window's
      -- buffer in a way winfixbuf's switch-check doesn't catch (only
      -- navigating further — opening a file or subdirectory — trips
      -- E1513), so a winfixbuf-protected PKM panel window can end up
      -- stuck showing an unusable netrw listing. Detected via
      -- winfixbuf+winfixwidth (sidebar) / winfixbuf+winfixheight (buffer
      -- panel) rather than views.lua/ui.lua's own tracked window id: the
      -- sidebar buffer's bufhidden='wipe' already destroyed it and cleared
      -- that per-tab state the moment netrw's buffer displaced it, before
      -- this callback ever runs — window-local options are the only signal
      -- left that survives the swap.
      do
        local win = vim.api.nvim_get_current_win()
        local wo  = vim.wo[win]
        local was_sidebar  = wo.winfixbuf and wo.winfixwidth
        local was_bufpanel = wo.winfixbuf and wo.winfixheight

        if was_sidebar or was_bufpanel then
          -- Defer the actual correction: this callback fires SYNCHRONOUSLY,
          -- NESTED inside netrw's own still-executing :Explore command
          -- (FileType autocmds run as part of the triggering command's
          -- call stack, not after it). Closing or reassigning the window
          -- from here — while netrw's script, further down that same call
          -- stack, still expects the window/buffer state it just set up to
          -- still exist — corrupts netrw's in-flight setup. Observed as an
          -- empty listing landing in whatever window ends up current, and
          -- (most likely the same root cause) window-layout bookkeeping
          -- left inconsistent enough to resurface the buffer-panel
          -- sole-window bug afterward. Letting netrw's command finish
          -- completely first, then reacting on the next event-loop tick,
          -- avoids fighting it mid-execution.
          vim.schedule(function()
            if not vim.api.nvim_win_is_valid(win) then return end

            vim.notify(
              '[pkm] cannot browse files inside a PKM panel — closing and reopening it',
              vim.log.levels.WARN)

            local non_float = 0
            for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
              if vim.api.nvim_win_get_config(w).relative == '' then
                non_float = non_float + 1
              end
            end

            if non_float <= 1 then
              local scratch = vim.api.nvim_create_buf(false, true)
              vim.bo[scratch].bufhidden = 'wipe'
              pcall(vim.api.nvim_set_option_value, 'winfixbuf', false, { win = win })
              vim.api.nvim_win_set_buf(win, scratch)
              pcall(vim.api.nvim_set_option_value, 'winfixbuf', true, { win = win })
            else
              pcall(vim.api.nvim_win_close, win, true)
            end

            vim.schedule(function()
              if was_sidebar then
                require('pkm.views').open_sidebar()
              else
                require('pkm.ui').toggle_bufpanel()
              end
            end)
          end)
          return
        end
      end

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
  map(k.next_header, "<cmd>PKMHeader append<cr>", "Append Header (increment counter)")

  -- Header navigation. Only the same-level pair is bound by default: `]]` and
  -- `[[` already jump header to header, so a key for that would spend a
  -- keystroke on what Neovim does. Same-level motion has no native equivalent,
  -- so it gets the keys — unmodified, in the bracket family the native motion
  -- already lives in.
  --
  -- Buffer-local on markdown, the way ftplugin/markdown.lua binds `]]`: a
  -- header motion means nothing in a Lua file, and a global mapping would take
  -- `]h` away everywhere for a command that could only answer "no headers".
  --
  -- Lua callbacks rather than <cmd> strings because v:count1 has to be read at
  -- press time, and because a callback keeps Visual mode active so the motion
  -- extends the selection.
  local motions = {
    { lhs = k.header_next,      dir = 'next', level = nil,    desc = 'next header' },
    { lhs = k.header_prev,      dir = 'prev', level = nil,    desc = 'previous header' },
    { lhs = k.header_next_same, dir = 'next', level = 'same', desc = 'next header of the same level' },
    { lhs = k.header_prev_same, dir = 'prev', level = 'same', desc = 'previous header of the same level' },
  }

  -- Relative-level jumps: <prefix>N = N levels shallower/deeper (exact delta),
  -- the digit baked into the key. All four direction × level combinations, since
  -- searching backward for a deeper header, or forward for a shallower one, are
  -- both meaningful (a descendant behind the cursor / an ancestor-level header
  -- ahead). The two "aligned" motions ([N, ]N) stay bare; the two "crossed" ones
  -- carry a level letter (l = lower/deeper, u = upper/shallower). N = 1..6, a
  -- target outside 1..6 just does not move.
  local MAX_HEADING_LEVEL = 6
  local level_jumps = {
    { prefix = k.header_prev_shallower_prefix, dir = 'prev', sign = -1, word = 'shallower, backward' },
    { prefix = k.header_next_deeper_prefix,    dir = 'next', sign =  1, word = 'deeper, forward' },
    { prefix = k.header_prev_deeper_prefix,    dir = 'prev', sign =  1, word = 'deeper, backward' },
    { prefix = k.header_next_shallower_prefix, dir = 'next', sign = -1, word = 'shallower, forward' },
  }

  local function bind_motions(bufnr)
    for _, m in ipairs(motions) do
      if m.lhs then
        vim.keymap.set({ 'n', 'x' }, m.lhs, function()
          require('pkm.markdown').goto_heading({
            dir = m.dir, count = vim.v.count1, level = m.level })
        end, { buffer = bufnr, desc = 'PKM: ' .. m.desc, silent = true })
      end
    end
    for _, j in ipairs(level_jumps) do
      if j.prefix then
        for n = 1, MAX_HEADING_LEVEL do
          local delta = j.sign * n
          vim.keymap.set({ 'n', 'x' }, j.prefix .. n, function()
            require('pkm.markdown').goto_heading({ dir = j.dir, level_delta = delta })
          end, { buffer = bufnr, silent = true,
                 desc = 'PKM: header ' .. n .. ' level(s) ' .. j.word })
        end
      end
    end
  end

  vim.api.nvim_create_autocmd('FileType', {
    group    = vim.api.nvim_create_augroup('PKMHeaderMotions', { clear = true }),
    pattern  = 'markdown',
    callback = function(ev) bind_motions(ev.buf) end,
  })

  -- Buffers already open when setup() runs never see that FileType event.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'markdown' then
      bind_motions(buf)
    end
  end

  if k.header_level_up then
    vim.keymap.set('n', k.header_level_up, '<cmd>PKMHeader levelup<cr>',
      { desc = "PKM: Header Level Up (buffer)", silent = true })
    vim.keymap.set('v', k.header_level_up, ':PKMHeader levelup<cr>',
      { desc = "PKM: Header Level Up (selection)", silent = true })
  end

  if k.header_level_down then
    vim.keymap.set('n', k.header_level_down, '<cmd>PKMHeader leveldown<cr>',
      { desc = "PKM: Header Level Down (buffer)", silent = true })
    vim.keymap.set('v', k.header_level_down, ':PKMHeader leveldown<cr>',
      { desc = "PKM: Header Level Down (selection)", silent = true })
  end

  if k.renumber_list then
    vim.keymap.set('n', k.renumber_list, '<cmd>PKMList renumber<cr>',
      { desc = 'PKM: Renumber sequence (paragraph)', silent = true })
    vim.keymap.set('v', k.renumber_list, ':PKMList renumber<cr>',
      { desc = 'PKM: Renumber sequence (selection)', silent = true })
  end

  if k.convert_list then
    vim.keymap.set('n', k.convert_list, '<cmd>PKMList convert<cr>',
      { desc = 'PKM: Convert list ordered/unordered (paragraph)', silent = true })
    vim.keymap.set('v', k.convert_list, ':PKMList convert<cr>',
      { desc = 'PKM: Convert list ordered/unordered (selection)', silent = true })
  end

  if k.toggle_syntax then
    vim.keymap.set('n', k.toggle_syntax, '<cmd>PKMSyntax toggle<cr>',
      { desc = 'PKM: Toggle markdown highlighting (buffer)', silent = true })
  end
end

return M
