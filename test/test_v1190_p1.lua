-- test/test_v1190_p1.lua
-- pkm.api.annotate — the marked-comment mechanism for writing into a note that
-- is NOT the assistant's own. The marker is baked in (not optional), the block
-- lands at a boundary (never inline), the frontmatter and the user's own text are
-- left intact, and it delegates to write_section/write_body (so the unsaved-buffer
-- guard and graph reconcile come for free).
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1190_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function lines_of(path) return vim.fn.readfile(path) end
local function file_has(path, needle)
  for _, l in ipairs(lines_of(path)) do if l:find(needle, 1, true) then return true end end
  return false
end
local function line_index(path, exact)
  for i, l in ipairs(lines_of(path)) do if l == exact then return i end end
  return nil
end
local function fm_title(path)
  local fm = require('pkm.yaml').parse_frontmatter(lines_of(path))
  return fm and fm.title
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

print("== a user note is annotated with a marked block at the note end ==")
-- A human-authored note (no `by`): the case annotate is meant for.
local u = api.create('note', { title = 'UserNote',
  body = 'This is what the user wrote.\n\n## Notes\nuser line under Notes' })
check("the user note was created without an author marker",
  u.ok and u.author == nil and u.filename:find('ByClaude', 1, true) == nil, vim.inspect(u))

local a1 = api.annotate(u.path, 'a first observation')
check("annotate returns ok", a1.ok, vim.inspect(a1))
check("the block carries the By Claude: marker",
  file_has(u.path, 'By Claude: a first observation'),
  vim.inspect(lines_of(u.path)))
check("the user's own text is untouched", file_has(u.path, 'This is what the user wrote.'))
check("the frontmatter is preserved", fm_title(u.path) == 'UserNote')
check("the marked block is a boundary block (a blank line precedes it)", (function()
  local i = line_index(u.path, 'By Claude: a first observation')
  return i and i > 1 and lines_of(u.path)[i - 1] == ''
end)(), vim.inspect(lines_of(u.path)))

print("\n== a custom author renders in the marker ==")
local a2 = api.annotate(u.path, 'from another agent', { by = 'assistant' })
check("annotate with by='assistant' marks By Assistant:",
  a2.ok and file_has(u.path, 'By Assistant: from another agent'), vim.inspect(lines_of(u.path)))

print("\n== annotate into a named section lands inside that section ==")
local a3 = api.annotate(u.path, 'note-scoped remark', { heading = 'Notes' })
check("annotate into 'Notes' returns ok", a3.ok, vim.inspect(a3))
check("the remark is marked and sits under the Notes heading, after the user line",
  (function()
    local ls = lines_of(u.path)
    local h, remark, userline
    for i, l in ipairs(ls) do
      if l == '## Notes' then h = i end
      if l == 'By Claude: note-scoped remark' then remark = i end
      if l == 'user line under Notes' then userline = i end
    end
    return h and userline and remark and h < userline and userline < remark
  end)(), vim.inspect(lines_of(u.path)))

print("\n== a citation token inside an annotation is reconciled into the graph ==")
local other = api.create('note', { title = 'Cited', by = 'claude' })
check("a target note exists", other.ok)
local a4 = api.annotate(u.path, string.format('see also [note[%04d]]', other.number))
check("annotate with a citation token returns ok", a4.ok, vim.inspect(a4))
check("the user note now cites the target (graph reconciled)", (function()
  local e = require('pkm.index').get(u.path)
  if not e then return false end
  -- The token was written into the body; update_references picks it up.
  return file_has(u.path, string.format('note[%04d]', other.number))
end)(), 'expected the citation token present after annotate')

print("\n== guards ==")
check("empty content is refused", not api.annotate(u.path, '').ok)
check("annotating a missing note is refused", not api.annotate('/no/such/note.md', 'x').ok)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
