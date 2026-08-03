-- test/test_v190_p2.lua
-- Tests for v1.9.0 Phase 2: a note created already inside a view.
--
-- Same question as adding a note to a view, asked before the note exists: which
-- tags make the filter match. Because the note is new it carries none, so only
-- the tags to *add* matter — and they are seeded at creation, so the note is
-- born matching instead of being edited into place afterwards.
--
-- Telescope never loads headless, so the panels that carry the key are
-- smoke-only; what is exercised here is the engine they all call, plus the
-- keymaps of the surfaces that are plain buffers.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v190_p2.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== a note born inside a view (v1.9.0 Ph2) ==")

local pkm   = require('pkm')
local utils = require('pkm.utils')
local index = require('pkm.index')
local views = require('pkm.views')
local tags  = require('pkm.tags')

-- This suite predates the sidebar autoswitch (v1.52.0) and asserts the VIEWS
-- provider's keymaps directly; open the sidebar deterministically by pinning it
-- (autoswitch off), so a markdown buffer being focused does not open nav instead.
views.set_autoswitch('off')

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')
index.rebuild()

views.save('v190p2_simples',   'tag:alfa')
views.save('v190p2_duplo',     'tag:alfa AND tag:beta')
views.save('v190p2_escolha',   'tag:gama OR tag:delta')
views.save('v190p2_bloqueado', 'tag:alfa AND title:impossivel')
views.save('v190p2_titulo',    'title:impossivel')

--- Run new_note_in_view with the type and title prompts answered.
---@param view  string
---@param title string
---@param pick  string|nil  Substring of the alternative to choose, when asked
---@return string|nil path
---@return string[]  notifications
local function create_in(view, title, pick)
  local said = {}
  local orig_notify, orig_select = vim.notify, vim.ui.select
  -- create_new_note asks for the title with `vim.fn.input`, not `vim.ui.input`,
  -- so that is what has to be answered here — headless, it would block forever.
  local orig_input = vim.fn.input
  vim.fn.input = function() return title end

  vim.notify = function(msg) said[#said + 1] = tostring(msg) end

  vim.ui.select = function(items, opts, on_choice)
    -- Two different menus reach here: the alternative chooser (rows are tables
    -- rendered by format_item) and create_new_note's own type prompt.
    for i, item in ipairs(items) do
      local label = opts.format_item and opts.format_item(item) or tostring(item)
      if pick and label:find(pick, 1, true) then on_choice(item, i) return end
    end
    on_choice(items[1], 1)
  end

  local done = false
  tags.new_note_in_view(view, { on_done = function() done = true end })
  vim.wait(2000, function() return done end, 20)

  vim.notify, vim.ui.select, vim.fn.input = orig_notify, orig_select, orig_input

  -- `create_new_note` returns a path only when it was given a type; asked for
  -- one, it prompts and recurses, and the outer call returns nil. What it does
  -- do in every case is open the new note, so that is where the path comes
  -- from — and "the note is open for editing" is worth asserting anyway.
  local opened = vim.api.nvim_buf_get_name(0)
  if opened == '' or not opened:match('%.md$') then return nil, said end
  return opened, said
end

---@param path string
---@return string[]
local function tags_of(path)
  index.invalidate(path)
  local entry = index.get(path)
  return (entry and entry.tags) or {}
end

-- =============================================================================
-- The tags are seeded at creation
-- =============================================================================

do
  local path = create_in('v190p2_simples', 'Nascida Simples')
  check("the note was created", path ~= nil and vim.fn.filereadable(path) == 1,
    tostring(path))
  check("it carries the view's tag",
    vim.tbl_contains(tags_of(path or ''), 'alfa'),
    table.concat(tags_of(path or ''), ','))
  check("and the view matches it without another write",
    vim.tbl_contains(views.match_all('v190p2_simples'), path),
    tostring(#views.match_all('v190p2_simples')))
end

do
  -- Two tags required: both are seeded, in one creation.
  local path = create_in('v190p2_duplo', 'Nascida Dupla')
  local t = tags_of(path or '')
  check("both required tags are seeded",
    vim.tbl_contains(t, 'alfa') and vim.tbl_contains(t, 'beta'),
    table.concat(t, ','))
  check("and the note is in the view",
    vim.tbl_contains(views.match_all('v190p2_duplo'), path))
end

do
  -- An OR gives two ways in, and choosing between them is a judgement.
  local path = create_in('v190p2_escolha', 'Nascida Delta', '+delta')
  local t = tags_of(path or '')
  check("the chosen alternative is the one seeded",
    vim.tbl_contains(t, 'delta') and not vim.tbl_contains(t, 'gama'),
    table.concat(t, ','))
end

-- =============================================================================
-- What tags cannot reach is said, not silently ignored
-- =============================================================================

do
  -- Half the filter is reachable: seed that half, and name the rest.
  local path, said = create_in('v190p2_bloqueado', 'Nascida Bloqueada')
  local text = table.concat(said, ' ')

  check("the reachable tag is still seeded",
    vim.tbl_contains(tags_of(path or ''), 'alfa'),
    table.concat(tags_of(path or ''), ','))
  check("and the condition in the way is named",
    text:find('also requires', 1, true) ~= nil, text)
  check("the note exists all the same",
    path ~= nil and vim.fn.filereadable(path) == 1, tostring(path))
end

do
  -- Nothing tags can do: still a note, still an explanation.
  local path, said = create_in('v190p2_titulo', 'Nascida Sem Tag')
  local text = table.concat(said, ' ')
  check("a title-only view still creates the note",
    path ~= nil and vim.fn.filereadable(path) == 1, tostring(path))
  check("and says tags cannot satisfy it",
    text:find('cannot be satisfied by tags', 1, true) ~= nil
    or text:find('also requires', 1, true) ~= nil, text)
end

do
  -- An unknown view is refused before anything is created.
  local before = #vim.fn.glob(utils.join(notes_dir, '*.md'), false, true)
  local said = {}
  local orig = vim.notify
  vim.notify = function(msg) said[#said + 1] = tostring(msg) end

  tags.new_note_in_view('v190p2_inexistente')
  vim.wait(300, function() return #said > 0 end, 10)
  vim.notify = orig

  check("an unknown view creates nothing",
    #vim.fn.glob(utils.join(notes_dir, '*.md'), false, true) == before)
  check("and says so", #said > 0, table.concat(said, ' '))
end

-- =============================================================================
-- The surfaces that are plain buffers carry the key
-- =============================================================================

do
  -- The sidebar is a real buffer, so its mapping is assertable here. The
  -- Telescope pickers are not, and stay smoke-only.
  views.open_sidebar()
  vim.wait(500, function() return views.is_sidebar_open() end, 10)

  local win = views.get_sidebar_win()
  local ok  = win ~= nil
  check("the sidebar opened", ok)

  if ok then
    local buf  = vim.api.nvim_win_get_buf(win)
    local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
    local has_N = false
    for _, m in ipairs(maps) do
      if m.lhs == 'N' then has_N = true end
    end
    check("and N is bound in it", has_N)
  end
end

do
  -- Creating *from* the sidebar. Panels set `winfixbuf`, so opening the new
  -- note from one is an E1513 unless something moves to an editing window
  -- first — which is what this used to hit.
  -- open_sidebar toggles, and the block above left it open.
  if not views.is_sidebar_open() then views.open_sidebar() end
  vim.wait(500, function() return views.is_sidebar_open() end, 10)
  local sw = views.get_sidebar_win()

  check("the sidebar is available for this case", sw ~= nil)
  if sw then
    vim.api.nvim_set_current_win(sw)
    check("we really are in the sidebar",
      vim.bo.filetype == 'pkm-sidebar', vim.bo.filetype)

    local said = {}
    local orig_notify, orig_select = vim.notify, vim.ui.select
    local orig_input = vim.fn.input
    vim.notify   = function(msg) said[#said + 1] = tostring(msg) end
    vim.ui.select = function(items, _, on_choice) on_choice(items[1], 1) end
    vim.fn.input = function() return 'Nascida Na Sidebar' end

    local ok = pcall(tags.new_note_in_view, 'v190p2_simples')
    vim.wait(1500, function() return vim.bo.filetype == 'markdown' end, 20)

    vim.notify, vim.ui.select, vim.fn.input = orig_notify, orig_select, orig_input

    check("creating from the sidebar raises nothing", ok,
      table.concat(said, ' '))
    check("and the note lands in a window that may hold it",
      require('pkm.utils').is_editing_win(vim.api.nvim_get_current_win())
      and vim.api.nvim_buf_get_name(0):match('%.md$') ~= nil,
      vim.bo.filetype .. ' / ' .. vim.api.nvim_buf_get_name(0))
  end
end

do
  -- The no-Telescope views panel is a panel.lua buffer, likewise assertable.
  views.open_views_panel('views')
  vim.wait(500, function() return false end, 10)

  local found, has_N = false, false
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_get_option_value('filetype', { buf = buf }):match('^pkm%-') then
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
        if m.lhs == 'N' then found, has_N = true, true end
        if m.lhs == 'n' then found = true end
      end
    end
  end
  check("the views panel binds N next to n", found and has_N)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
