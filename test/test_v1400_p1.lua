-- test/test_v1400_p1.lua
-- syntax — legal-marker highlighting for the levels tree-sitter cannot see:
-- artigo (Art. Nº) and parágrafo (§ Nº) via matchadd patterns, and subalínea
-- (i.) via a validated buffer scan (find_subalinea_markers) + extmarks. This test
-- pins the patterns and the scan; the visual result rides the real-config smoke.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1400_p1.lua" -c "qa!"

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

print("== artigo / parágrafo patterns are exposed and match/reject ==")
check("artigo_list_pattern exposed", type(syntax.artigo_list_pattern) == 'string')
check("paragrafo_list_pattern exposed", type(syntax.paragrafo_list_pattern) == 'string')

local art, par = syntax.artigo_list_pattern, syntax.paragrafo_list_pattern
local pat_cases = {
  { art, 'Art. 1º texto', 'Art. 1º' },
  { art, 'Art. 10 texto', 'Art. 10' },
  { art, '  Art. 3º indentado', 'Art. 3º' },
  { art, '> Art. 2º citado', 'Art. 2º' },
  { art, 'Art. is short for artigo', '' },   -- no digit → prose
  { par, '§ 1º texto', '§ 1º' },
  { par, '§ 10 texto', '§ 10' },
  { par, '§ is a symbol', '' },
}
for _, c in ipairs(pat_cases) do
  local got = vim.fn.matchstr(c[2], c[1])
  check(string.format('"%s" -> "%s"', c[2], c[3]), got == c[3], 'got "' .. got .. '"')
end

print("== subalínea scan finds valid roman markers and rejects words ==")
check("_find_subalinea_markers exposed", type(syntax._find_subalinea_markers) == 'function')

local lines = {
  'i. primeiro',            -- 1 marker
  '  ii. indentado',        -- 2 marker (indented)
  '> iii. citado',          -- 3 marker (blockquote)
  'iv.',                    -- 4 marker (empty item, EOL)
  'xiii. treze',            -- 5 marker
  'civil. palavra',         -- reject (not canonical roman)
  'mil. mil palavras',      -- reject
  'a) alinea',              -- reject (letter + paren)
  'texto i. inline',        -- reject (not line start)
}
local found = syntax._find_subalinea_markers(lines)
local by_row = {}
for _, m in ipairs(found) do by_row[m.row] = m end

check("found exactly the five real markers", #found == 5, '#found=' .. #found)
check("row 0 'i.' marker spans cols 0..2", by_row[0] and by_row[0].sc == 0 and by_row[0].ec == 2,
  vim.inspect(by_row[0]))
check("row 1 '  ii.' marker starts after 2-space indent",
  by_row[1] and by_row[1].sc == 2 and by_row[1].ec == 5, vim.inspect(by_row[1]))
check("row 3 empty 'iv.' at EOL is found", by_row[3] ~= nil, vim.inspect(by_row[3]))
check("row 4 'xiii.' is found", by_row[4] ~= nil, vim.inspect(by_row[4]))
check("civil. (row 5) rejected", by_row[5] == nil)
check("mil. (row 6) rejected", by_row[6] == nil)
check("a) (row 7) rejected", by_row[7] == nil)
check("inline i. (row 8) rejected", by_row[8] == nil)

print("== the highlight group PKMListMarker is defined ==")
-- setup_hl_groups runs on enable/ColorScheme; call enable on a scratch buffer.
local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'i. one', 'ii. two' })
vim.bo[buf].filetype = 'markdown'
syntax.enable(buf)
vim.wait(400, function() return false end)
local hl = vim.api.nvim_get_hl(0, { name = 'PKMListMarker' })
check("PKMListMarker links to @markup.list", hl.link == '@markup.list', vim.inspect(hl))
local marks = vim.api.nvim_buf_get_extmarks(buf,
  vim.api.nvim_create_namespace('pkm_subalinea'), 0, -1, {})
check("subalínea extmarks were placed for i./ii.", #marks == 2, '#marks=' .. #marks)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
