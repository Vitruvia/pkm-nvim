-- test/test_xml_marker.lua
-- syntax — Item 4: XML/angle-bracket marker highlighting via the matchadd
-- pattern M.xml_tag_pattern. Pins the pattern (match/reject) and that the
-- PKMXmlTag highlight group is defined on enable. The visual result rides the
-- real-config smoke; matchadd is invisible to a headless-parsed buffer.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_xml_marker.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local syntax = require('pkm.syntax')

-- matchadd honours 'ignorecase' (the real config sets it); assert under it.
vim.o.ignorecase = true

print("== xml_tag_pattern is exposed and matches/rejects ==")
check("xml_tag_pattern exposed", type(syntax.xml_tag_pattern) == 'string')

local pat = syntax.xml_tag_pattern
local cases = {
  { '<deslocamento_exemplo-1>', '<deslocamento_exemplo-1>' },  -- underscore placeholder
  { '<deslocamento-exemplo-1>', '<deslocamento-exemplo-1>' },  -- hyphen tag
  { '</close>', '</close>' },                                  -- closing tag
  { '<br/>', '<br/>' },                                        -- self-closing
  { '<tag attr="x">', '<tag attr="x">' },                      -- with attribute
  { 'text <inline> more', '<inline>' },                        -- inline tag
  { 'if a < b and c > d then', '' },                           -- comparison — reject
  { 'value <3 heart', '' },                                    -- emoticon — reject
  { 'no angles here', '' },                                    -- plain — reject
  { '<3', '' },                                                -- reject
}
for _, c in ipairs(cases) do
  local got = vim.fn.matchstr(c[1], pat)
  check(string.format('"%s" -> "%s"', c[1], c[2]), got == c[2], 'got "' .. got .. '"')
end

print("== the highlight group PKMXmlTag is defined on enable ==")
local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '<deslocamento-exemplo-1>', 'text' })
vim.bo[buf].filetype = 'markdown'
syntax.enable(buf)
vim.wait(400, function() return false end)
local hl = vim.api.nvim_get_hl(0, { name = 'PKMXmlTag' })
check("PKMXmlTag links to Identifier", hl.link == 'Identifier', vim.inspect(hl))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
if failures > 0 then vim.cmd("cquit 1") end
