-- test/test_v1120_p5.lua
-- v1.12.0 Ph5 — agent authorship, and the deletion guard.
--
-- A note an agent writes is marked in its name (NNNN_type_By<Author>_slug), and
-- the agent deletion path may remove only notes that carry such a mark — an
-- agent working inside a human's vault must not delete what a human wrote. The
-- mark is read from the name, not frontmatter, so it survives a copy or a move.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1120_p5.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm   = require('pkm')
local yaml  = require('pkm.yaml')
local notes = require('pkm.notes')

local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

print("== :PKMNote new by=Claude marks authorship in the name ==")

vim.cmd('PKMNote new note title=Idea by=Claude')
local agent_note = vim.fn.expand('%:p')
check("the filename carries the ByClaude marker",
  agent_note:gsub('\\', '/'):find('/0001_note_ByClaude_Idea%.md$') ~= nil,
  vim.fn.fnamemodify(agent_note, ':t'))
check("agent_authored reads the author back", notes.agent_authored(agent_note) == 'Claude',
  tostring(notes.agent_authored(agent_note)))

local fm = yaml.parse_frontmatter(vim.fn.readfile(agent_note))
check("and the author is recorded in the frontmatter too", fm.author == 'Claude',
  tostring(fm.author))

print("== a note lowercased in the argument is still capitalised in the mark ==")

vim.cmd('PKMNote new note title=Two by=claude')
local agent2 = vim.fn.expand('%:p')
check("by=claude → ByClaude", notes.agent_authored(agent2) == 'Claude',
  vim.fn.fnamemodify(agent2, ':t'))

print("\n== an ordinary note carries no marker ==")

vim.cmd('PKMNote new note title=Human')
local human_note = vim.fn.expand('%:p')
check("a note with no by= is not agent-authored",
  notes.agent_authored(human_note) == nil, tostring(notes.agent_authored(human_note)))

print("\n== agent_delete removes only what an agent authored ==")

local ok_human, err_human = notes.agent_delete(human_note)
check("deleting a human note is refused", ok_human == false)
check("and says why", (err_human or ''):find('no agent authored', 1, true) ~= nil, err_human)
check("the human note is untouched", vim.fn.filereadable(human_note) == 1)

local ok_agent, who = notes.agent_delete(agent_note)
check("deleting an agent note succeeds", ok_agent == true)
check("and reports the author", who == 'Claude', tostring(who))
check("the note is gone from its place", vim.fn.filereadable(agent_note) == 0)

-- Trashed, not hard-deleted: an over-eager agent is recoverable.
local trash = require('pkm.trash')
local in_trash = false
for _, e in ipairs(trash.list()) do
  if e.filename == '0001_note_ByClaude_Idea.md' then in_trash = true end
end
check("it went to the trash, not oblivion", in_trash)

print("\n== the marker is a property of the name, so it survives a move ==")

-- Simulate a copy into another folder under the root: the mark travels.
local moved = root .. '/03-Consolidated/0009_note_ByClaude_moved.md'
vim.fn.writefile({ '---', 'title: moved', '---', '', 'x' }, moved)
check("a moved/copied agent note is still recognised",
  notes.agent_authored(moved) == 'Claude', tostring(notes.agent_authored(moved)))

print("\n== a non-existent path is refused, not silently ignored ==")

local ok_missing, err_missing = notes.agent_delete(root .. '/03-Consolidated/nope.md')
check("deleting a missing note is refused", ok_missing == false)
check("with a not-found message", (err_missing or ''):find('not found', 1, true) ~= nil, err_missing)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
