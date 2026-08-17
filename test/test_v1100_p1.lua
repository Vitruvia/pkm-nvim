-- test/test_v1100_p1.lua
-- Tests for v1.10.0 Phase 1: header navigation.
--
-- The targeting is pure, so almost all of it is checked as a function over one
-- fixture rather than through the cursor. The fixture is built out of the
-- lines that a naive `^#` scan gets wrong: a `#` comment inside YAML
-- frontmatter, a `#` comment inside a fenced code block, a `#hashtag` with no
-- space, seven hashes, three leading spaces, and a bare `#`.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1100_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== header navigation (v1.10.0 Ph1) ==")

local md = require('pkm.markdown')

-- =============================================================================
-- Fixture — headings are lines 7(1) 12(2) 18(3) 20(2) 22(1) 26(6) 27(1)
-- =============================================================================

local fx = {
  '---',                              --  1
  'title: Fixture',                   --  2
  '# not a heading: a YAML comment',  --  3
  'tags: []',                         --  4
  '---',                              --  5
  '',                                 --  6
  '# Level one',                      --  7
  '',                                 --  8
  'text',                             --  9
  '#hashtag',                         -- 10
  '',                                 -- 11
  '## Level two A',                   -- 12
  '',                                 -- 13
  '```sh',                            -- 14
  '# a shell comment',                -- 15
  '```',                              -- 16
  '',                                 -- 17
  '### Level three',                  -- 18
  '',                                 -- 19
  '## Level two B',                   -- 20
  '',                                 -- 21
  '   # three spaces still counts',   -- 22
  '',                                 -- 23
  '####### seven hashes do not',      -- 24
  '',                                 -- 25
  '###### Level six',                 -- 26
  '#',                                -- 27
}

---@return string
local function target(cursor, opts)
  return tostring(md.find_heading_target(fx, cursor, opts))
end

-- =============================================================================
-- Direction and boundaries
-- =============================================================================

check("the first jump lands on the first heading",
  target(1, { dir = 'next' }) == '7', target(1, { dir = 'next' }))
check("next is the default direction",
  target(1, nil) == '7', target(1, nil))
check("the cursor's own line never matches",
  target(7, { dir = 'next' }) == '12', target(7, { dir = 'next' }))
check("prev walks back",
  target(20, { dir = 'prev' }) == '18', target(20, { dir = 'prev' }))
check("nothing before the first heading",
  target(7, { dir = 'prev' }) == 'nil', target(7, { dir = 'prev' }))
check("nothing after the last heading",
  target(27, { dir = 'next' }) == 'nil', target(27, { dir = 'next' }))

-- =============================================================================
-- What is not a heading
-- =============================================================================

-- Frontmatter is skipped: the only heading before line 7 would be the YAML
-- comment on line 3, and the boundary check above already proves it is not
-- reachable. The fence and the rest are checked directly.
check("a '#' comment inside a code fence is skipped",
  target(12, { dir = 'next' }) == '18', target(12, { dir = 'next' }))
check("a #hashtag with no space is not a heading",
  target(9, { dir = 'next' }) == '12', target(9, { dir = 'next' }))
check("seven hashes are not a heading",
  target(22, { dir = 'next' }) == '26', target(22, { dir = 'next' }))
check("three leading spaces still count",
  target(21, { dir = 'next' }) == '22', target(21, { dir = 'next' }))
check("a bare '#' is a level-1 heading",
  target(26, { dir = 'next' }) == '27', target(26, { dir = 'next' }))

-- =============================================================================
-- Count
-- =============================================================================

check("a count of 2 skips one heading",
  target(7, { dir = 'next', count = 2 }) == '18', target(7, { count = 2 }))
check("a count of 3 skips two",
  target(7, { dir = 'next', count = 3 }) == '20', target(7, { count = 3 }))
check("a backwards count",
  target(26, { dir = 'prev', count = 3 }) == '18',
  target(26, { dir = 'prev', count = 3 }))
check("an overshooting count clamps to the last heading",
  target(7, { dir = 'next', count = 99 }) == '27', target(7, { count = 99 }))
check("an overshooting count backwards clamps to the first",
  target(27, { dir = 'prev', count = 99 }) == '7',
  target(27, { dir = 'prev', count = 99 }))
check("count 0 and count nil behave the same",
  target(7, { count = 0 }) == target(7, {}), target(7, { count = 0 }))

-- =============================================================================
-- Level restriction — the gap in Neovim's native ]] / [[
-- =============================================================================

check("level 2 skips levels 1 and 3",
  target(1, { level = 2 }) == '12', target(1, { level = 2 }))
check("level 2 twice reaches the second one",
  target(1, { level = 2, count = 2 }) == '20', target(1, { level = 2, count = 2 }))
check("level 6 reaches the only one",
  target(1, { level = 6 }) == '26', target(1, { level = 6 }))
check("a level with no headings gives nil",
  target(1, { level = 4 }) == 'nil', target(1, { level = 4 }))
check("'same' takes the level of the enclosing heading",
  target(13, { level = 'same' }) == '20', target(13, { level = 'same' }))
check("'same' from inside a level-1 section skips every deeper heading",
  target(9, { level = 'same' }) == '22', target(9, { level = 'same' }))
check("'same' backwards",
  target(27, { level = 'same', dir = 'prev' }) == '22',
  target(27, { level = 'same', dir = 'prev' }))
check("'same' above every heading falls back to any level",
  target(1, { level = 'same' }) == '7', target(1, { level = 'same' }))

-- =============================================================================
-- Relative level — exact delta from the enclosing section (the [N / ]N keys)
-- =============================================================================

-- Cursor on line 19, inside the '### Level three' section (heading on 18, L3).
check("delta -1 backward is the parent ## (L2 before)",
  target(19, { dir = 'prev', level_delta = -1 }) == '12',
  target(19, { dir = 'prev', level_delta = -1 }))
check("delta -2 backward is the grandparent # (L1 before)",
  target(19, { dir = 'prev', level_delta = -2 }) == '7',
  target(19, { dir = 'prev', level_delta = -2 }))
check("delta +3 forward is the exact L6 header (n+3)",
  target(19, { dir = 'next', level_delta = 3 }) == '26',
  target(19, { dir = 'next', level_delta = 3 }))
check("delta +1 with no L4 heading present does not move (exact, not >=)",
  target(19, { dir = 'next', level_delta = 1 }) == 'nil',
  target(19, { dir = 'next', level_delta = 1 }))
check("delta below level 1 matches nothing (cannot go shallower than #)",
  target(19, { dir = 'prev', level_delta = -5 }) == 'nil',
  target(19, { dir = 'prev', level_delta = -5 }))
-- Cursor on line 13, inside '## Level two A' (heading on 12, L2).
check("delta +1 from a level-2 section is the L3 below it",
  target(13, { dir = 'next', level_delta = 1 }) == '18',
  target(13, { dir = 'next', level_delta = 1 }))
check("level_delta overrides an explicit level",
  target(19, { dir = 'prev', level_delta = -1, level = 6 }) == '12',
  target(19, { dir = 'prev', level_delta = -1, level = 6 }))
check("level_delta above every heading falls back to any level",
  target(1, { dir = 'next', level_delta = -1 }) == '7',
  target(1, { dir = 'next', level_delta = -1 }))
-- The two "crossed" motions: dir and level_delta are independent, so a deeper
-- header can be sought BACKWARD and a shallower one FORWARD.
-- Cursor on line 21 (inside '## Level two B' at 20, L2); an L3 (18) is behind it.
check("crossed: deeper backward finds the L3 before the cursor",
  target(21, { dir = 'prev', level_delta = 1 }) == '18',
  target(21, { dir = 'prev', level_delta = 1 }))
-- Cursor on line 19 (inside '### Level three' at 18, L3); an L2 (20) is ahead.
check("crossed: shallower forward finds the L2 after the cursor",
  target(19, { dir = 'next', level_delta = -1 }) == '20',
  target(19, { dir = 'next', level_delta = -1 }))
check("crossed: shallower forward, 2 levels, reaches the L1 after",
  target(19, { dir = 'next', level_delta = -2 }) == '22',
  target(19, { dir = 'next', level_delta = -2 }))

-- =============================================================================
-- Degenerate input
-- =============================================================================

check("no headings gives nil",
  tostring(md.find_heading_target({ 'text', '', 'more' }, 1, {})) == 'nil')
check("an empty buffer gives nil",
  tostring(md.find_heading_target({}, 1, {})) == 'nil')
check("nil lines gives nil",
  tostring(md.find_heading_target(nil, 1, {})) == 'nil')

-- =============================================================================
-- goto_heading — the cursor, in a real window
-- =============================================================================

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, fx)

---@return integer, integer
local function jump(from, opts)
  vim.api.nvim_win_set_cursor(0, { from, 0 })
  local moved = md.goto_heading(opts)
  local pos   = vim.api.nvim_win_get_cursor(0)
  return pos[1], pos[2], moved
end

local lnum, col, moved = jump(1, { dir = 'next' })
check("goto_heading moves the cursor and reports it",
  lnum == 7 and col == 0 and moved == true,
  string.format('%d,%d,%s', lnum, col, tostring(moved)))

lnum, col = jump(21, { dir = 'next' })
check("the cursor lands on the '#', not on the indent",
  lnum == 22 and col == 3, string.format('%d,%d', lnum, col))

lnum, col, moved = jump(27, { dir = 'next' })
check("at the last heading the cursor stays put and it reports false",
  lnum == 27 and col == 0 and moved == false,
  string.format('%d,%d,%s', lnum, col, tostring(moved)))

lnum = jump(13, { dir = 'next', level = 'same' })
check("goto_heading passes the level through",
  lnum == 20, tostring(lnum))

vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! 25G')
md.goto_heading({ dir = 'prev' })
vim.cmd('normal! \x0f')   -- <C-o>
check("the jump leaves a jumplist entry, so <C-o> comes back",
  vim.api.nvim_win_get_cursor(0)[1] == 25,
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

-- =============================================================================
-- Keymaps — buffer-local on markdown, and nowhere else
-- =============================================================================

---@return string  the ]h / [h mappings found, sorted, as one string
local function motion_maps(bufnr)
  local found = {}
  for _, mode in ipairs({ 'n', 'x' }) do
    local maps = bufnr and vim.api.nvim_buf_get_keymap(bufnr, mode)
                        or vim.api.nvim_get_keymap(mode)
    for _, m in ipairs(maps) do
      -- keytrans: the lhs comes back with raw control bytes, so a plain
      -- string comparison silently finds nothing (v1.9.0 learned this).
      local lhs = vim.fn.keytrans(m.lhs)
      if lhs == ']h' or lhs == '[h' then found[#found + 1] = mode .. lhs end
    end
  end
  table.sort(found)
  return table.concat(found, ' ')
end

check("the motions are not global",
  motion_maps(nil) == '', motion_maps(nil))
check("nor bound in a buffer that is not markdown",
  motion_maps(buf) == '', motion_maps(buf))

vim.bo[buf].filetype = 'markdown'
check("markdown gets them, in normal and visual",
  motion_maps(buf) == 'n[h n]h x[h x]h', motion_maps(buf))

vim.api.nvim_win_set_cursor(0, { 12, 0 })
vim.cmd('normal ]h')      -- no bang: `normal!` would ignore the mapping
check("]h holds the level",
  vim.api.nvim_win_get_cursor(0)[1] == 20,
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

vim.cmd('normal [h')
check("[h holds it too", vim.api.nvim_win_get_cursor(0)[1] == 12,
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

vim.api.nvim_win_set_cursor(0, { 7, 0 })
vim.cmd('normal 2]h')
check("a count reaches the second one of that level",
  vim.api.nvim_win_get_cursor(0)[1] == 27,
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

-- =============================================================================
-- Commands
-- =============================================================================

check(":PKMHeader is registered", vim.fn.exists(':PKMHeader') == 2)
check("the ambiguous PKMNextHeader is gone",
  vim.fn.exists(':PKMNextHeader') == 0, tostring(vim.fn.exists(':PKMNextHeader')))

vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('PKMHeader next')
check(":PKMHeader next jumps", vim.api.nvim_win_get_cursor(0)[1] == 7,
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

-- The context form takes the count as an argument, not a Vim prefix (:PKMHeader
-- carries a range for its level-shifts, which a count prefix would collide with;
-- the prefix ergonomic lives on the header-motion keymaps instead).
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('PKMHeader next 3')
check("a count argument is honoured", vim.api.nvim_win_get_cursor(0)[1] == 18,
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

-- From line 7 the two readings of "2" diverge: the second header ahead is 18,
-- the first level-2 header ahead is 12.
vim.api.nvim_win_set_cursor(0, { 7, 0 })
vim.cmd('PKMHeader next h2')
check("a level argument is honoured", vim.api.nvim_win_get_cursor(0)[1] == 12,
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

vim.api.nvim_win_set_cursor(0, { 7, 0 })
vim.cmd('PKMHeader next 2')
check("a bare number argument is the count",
  vim.api.nvim_win_get_cursor(0)[1] == 18,
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

vim.api.nvim_win_set_cursor(0, { 7, 0 })
vim.cmd('PKMHeader next h2 2')
check("count and level compose",
  vim.api.nvim_win_get_cursor(0)[1] == 20,
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

vim.api.nvim_win_set_cursor(0, { 27, 0 })
vim.cmd('PKMHeader prev same')
check("'same' as an argument is honoured",
  vim.api.nvim_win_get_cursor(0)[1] == 22,
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

vim.api.nvim_win_set_cursor(0, { 1, 0 })
local ok_bad = pcall(vim.cmd, 'PKMHeader next nonsense')
check("a bad level argument warns instead of moving",
  ok_bad and vim.api.nvim_win_get_cursor(0)[1] == 1,
  string.format('%s,%d', tostring(ok_bad), vim.api.nvim_win_get_cursor(0)[1]))

-- =============================================================================

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
