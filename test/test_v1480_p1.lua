-- test/test_v1480_p1.lua
-- pkm.nav — current-file navigation. The heading index core (_headings_of):
-- level indentation, a title header, the display→source map, fence/frontmatter
-- skipping (via markdown.scan_headings), and text filtering. Plus integration:
-- since Phase 3.3a nav is a CONTENT PROVIDER in the one sidebar (not its own
-- container), reached via views.show_sidebar_provider('nav') and the cycle key.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1480_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end

local pkm  = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })
local nav = require('pkm.nav')

local function mkbuf(lines, name)
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  if name then vim.api.nvim_buf_set_name(b, name) end
  vim.bo[b].filetype = 'markdown'
  return b
end

print("== _headings_of: levels, title header, map, code-fence skipping ==")
local buf = mkbuf({
  '# Top',            -- 1
  'text',             -- 2
  '## Sub A',         -- 3
  '### Deep',         -- 4
  '## Sub B',         -- 5
  '```',              -- 6
  '# not a heading',  -- 7  (inside a code fence → skipped)
  '```',              -- 8
}, '/tmp/note.md')
local lines, map = nav._headings_of(buf, '')
check("title header first (filename)", lines[1]:find('note.md', 1, true) ~= nil, lines[1])
check("Top at level-1 indent (none)", lines[2] == 'Top', lines[2])
check("Sub A indented 2", lines[3] == '  Sub A', lines[3])
check("Deep indented 4", lines[4] == '    Deep', lines[4])
check("Sub B indented 2", lines[5] == '  Sub B', lines[5])
check("exactly 4 headings (the # in code is skipped)", #lines == 5, #lines)
check("map row2 → source line 1 (Top)", map[2] == 1, tostring(map[2]))
check("map row4 → source line 4 (Deep)", map[4] == 4, tostring(map[4]))
check("title-header row is not jumpable", map[1] == nil)

print("== filter is a case-insensitive substring over heading text ==")
local flines, fmap = nav._headings_of(buf, 'sub')
check("filter 'sub' → header + 2 matches", #flines == 3, #flines)
check("filtered map still points at source lines", fmap[2] == 3 and fmap[3] == 5,
  tostring(fmap[2]) .. ',' .. tostring(fmap[3]))
local nomatch = nav._headings_of(buf, 'zzz')
check("no-match placeholder", nomatch[2]:find('no match', 1, true) ~= nil, nomatch[2])

print("== a note with no headings shows a placeholder ==")
local plain = mkbuf({ 'just text', 'more' }, '/tmp/plain.md')
local plines = nav._headings_of(plain, '')
check("(no headings) placeholder", plines[2]:find('no headings', 1, true) ~= nil, plines[2])

print("== frontmatter is skipped (# inside it is not a heading) ==")
local fm = mkbuf({ '---', 'title: x', '# comment', '---', '# Real', '## Also' }, '/tmp/fm.md')
local fmlines, fmmap = nav._headings_of(fm, '')
check("only the two body headings", #fmlines == 3, #fmlines)
check("first body heading maps to line 5", fmmap[2] == 5, tostring(fmmap[2]))

print("== integration: nav is CONTENT in the one sidebar (not its own container) ==")
local notef = vim.fn.tempname() .. '/n.md'
vim.fn.mkdir(vim.fn.fnamemodify(notef, ':h'), 'p')
vim.fn.writefile({ '# Alpha', 'x', '## Beta', 'y' }, notef)
vim.cmd('edit ' .. vim.fn.fnameescape(notef))
vim.bo.filetype = 'markdown'

local views = require('pkm.views')
local shown = views.sidebar_provider()
if shown then views.show_sidebar_provider(shown) end   -- toggle whatever is open closed
check("sidebar starts closed", not views.is_sidebar_open())

views.show_sidebar_provider('nav')
check("the sidebar opened on the nav provider",
  views.is_sidebar_open() and views.sidebar_provider() == 'nav',
  tostring(views.sidebar_provider()))
local sw = views.get_sidebar_win()
check("nav renders inside the pkm-sidebar container (no separate pkm-nav window)",
  vim.bo[vim.api.nvim_win_get_buf(sw)].filetype == 'pkm-sidebar',
  vim.bo[vim.api.nvim_win_get_buf(sw)].filetype)
local joined = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sw), 0, -1, false), '\n')
check("the sidebar shows the note's headings (Alpha)", joined:find('Alpha', 1, true) ~= nil, joined)
check("and Beta", joined:find('Beta', 1, true) ~= nil, joined)

views.cycle_sidebar_provider()
check("cycle switches the same container to views",
  views.is_sidebar_open() and views.sidebar_provider() == 'views',
  tostring(views.sidebar_provider()))
check("still the one pkm-sidebar container",
  vim.bo[vim.api.nvim_win_get_buf(views.get_sidebar_win())].filetype == 'pkm-sidebar')

views.cycle_sidebar_provider()
check("cycle back to nav", views.sidebar_provider() == 'nav')
views.show_sidebar_provider('nav')   -- already on nav → toggles closed
check("showing the active provider again closes the sidebar", not views.is_sidebar_open())

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
