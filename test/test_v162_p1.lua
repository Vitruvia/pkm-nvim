-- test/test_v162_p1.lua
-- Tests for v1.6.2 Phase 1: the faster index build.
--
-- The phase replaced two per-file VimL calls in the build path with LuaJIT/libuv
-- equivalents (`vim.fn.glob` → `uv.fs_scandir`, `vim.fn.readfile` →
-- `utils.read_lines`). Both are normalisation-sensitive, so this file is an
-- equivalence test, not a feature test: it rebuilds the reference result with
-- the *old* primitives and demands the index match it field by field.
--
-- Runs against a real headless Neovim instance on the disposable temp root
-- created by test/min_init.lua — never the live Notes tree.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v162_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== index build equivalence (v1.6.2 Ph1) ==")

local pkm   = require('pkm')
local utils = require('pkm.utils')
local yaml  = require('pkm.yaml')
local index = require('pkm.index')

-- =============================================================================
-- Part A — utils.read_lines() vs vim.fn.readfile(), byte for byte
-- =============================================================================

local probe_dir = vim.fn.tempname() .. '_v162_reader'
vim.fn.mkdir(probe_dir, 'p')

--- Write raw bytes (no line-ending translation) and return the path.
---@param name  string
---@param bytes string
---@return string path
local function write_raw(name, bytes)
  local path = utils.join(probe_dir, name)
  local f = assert(io.open(path, 'wb'))
  f:write(bytes)
  f:close()
  return path
end

local reader_cases = {
  lf           = 'a\nb\nc\n',
  crlf         = 'a\r\nb\r\nc\r\n',
  mixed_ending = 'a\r\nb\nc\r\n',
  no_final_nl  = 'a\nb',
  final_cr     = 'a\nb\r',           -- CR at EOF with no LF: readfile keeps it
  bom          = '\239\187\191---\ntitle: x\n---\nbody\n',
  bom_crlf     = '\239\187\191---\r\ntitle: x\r\n---\r\nbody\r\n',
  empty        = '',
  only_nl      = '\n',
  two_nl       = '\n\n',
  blank_body   = '---\ntitle: x\n---\n\n\n',
  accents      = '---\ntitle: "A\u{00e7}\u{00e3}o"\n---\ncaf\u{00e9} com p\u{00e3}o\n',
  long_line    = '---\ntitle: x\n---\n' .. string.rep('z', 5000) .. '\n',
}

for name, bytes in pairs(reader_cases) do
  local path = write_raw(name .. '.md', bytes)
  local expected = vim.fn.readfile(path)
  local actual   = utils.read_lines(path)

  local same, detail = #expected == #actual, nil
  if not same then
    detail = string.format('readfile=%d lines, read_lines=%d lines', #expected, #actual)
  else
    for i = 1, #expected do
      if expected[i] ~= actual[i] then
        same   = false
        detail = string.format('line %d: %q vs %q', i, expected[i], actual[i])
        break
      end
    end
  end
  check("read_lines matches readfile: " .. name, same, detail)
end

check("read_lines returns nil for a missing file",
  utils.read_lines(utils.join(probe_dir, 'does-not-exist.md')) == nil)

vim.fn.delete(probe_dir, 'rf')

-- =============================================================================
-- Fixture for the build-level checks
-- =============================================================================

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

--- write_raw, but into an arbitrary directory.
---@param dir   string
---@param name  string
---@param bytes string
---@return string path
local function write_raw_at(dir, name, bytes)
  local path = utils.join(dir, name)
  local f = assert(io.open(path, 'wb'))
  f:write(bytes)
  f:close()
  return path
end

--- Frontmatter + body, written with the requested line ending.
---@param stem   string
---@param tags   string[]
---@param eol    string   '\n' or '\r\n'
---@param prefix string|nil  Bytes before the frontmatter (e.g. a BOM)
---@return string path
local function write_note(stem, tags, eol, prefix)
  local lines = { '---', string.format('title: "%s"', stem), 'tags:' }
  for _, t in ipairs(tags) do lines[#lines + 1] = '  - ' .. t end
  lines[#lines + 1] = 'cites:'
  lines[#lines + 1] = '  notes:'
  lines[#lines + 1] = '    - 00099_note_somewhere'
  lines[#lines + 1] = '---'
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'Body of ' .. stem .. ' with MiXeD case.'
  return write_raw_at(notes_dir, stem .. '.md',
    (prefix or '') .. table.concat(lines, eol) .. eol)
end

write_note('00101_note_lf_plain',  { 'alpha' },          '\n')
write_note('00102_note_crlf',      { 'alpha', 'Beta' },  '\r\n')
write_note('00103_note_bom',       { 'gamma' },          '\n', '\239\187\191')
write_note('00104_note_no_tags',   {},                   '\n')
write_note('journal_2026-07-24',   { 'diary' },          '\n')

-- Uppercase extension: glob matched it on Windows/WSL and not on Linux, and
-- Part C below compares the index against exactly what glob lists, so this file
-- asserts the platform rule is reproduced rather than assuming either answer.
write_raw_at(notes_dir, '00108_note_upper_ext.MD',
  '---\ntitle: "Upper"\n---\nbody\n')

-- Files that must NOT become index entries.
write_raw_at(notes_dir, '00105_note_empty.md', '')
write_raw_at(notes_dir, '00106_note_no_frontmatter.md', 'just text, no frontmatter\n')
write_raw_at(notes_dir, 'not_a_note.txt', '---\ntitle: x\n---\nbody\n')
vim.fn.mkdir(utils.join(notes_dir, 'subdir'), 'p')
write_raw_at(utils.join(notes_dir, 'subdir'), 'nested.md', '---\ntitle: n\n---\nbody\n')

index.rebuild()

-- =============================================================================
-- Part B — the listing: same files as vim.fn.glob would have produced
-- =============================================================================

local globbed = vim.fn.glob(notes_dir .. utils.sep .. '*.md', false, true)
local expected_paths = {}
for _, p in ipairs(globbed) do
  expected_paths[utils.normalize(p):lower()] = true
end

local indexed_paths = {}
for _, e in ipairs(index.get_all()) do
  indexed_paths[utils.normalize(e.path):lower()] = true
end

-- Every indexed file must be one glob would have listed. (The converse does not
-- hold: files without parseable frontmatter are listed but never indexed.)
local extra
for p in pairs(indexed_paths) do
  if not expected_paths[p] then extra = p break end
end
check("index contains no file outside glob's listing", extra == nil, extra)

check("nested .md is not indexed (listing stays non-recursive)",
  indexed_paths[utils.normalize(utils.join(notes_dir, 'subdir', 'nested.md')):lower()] == nil)
check("non-.md file is not indexed",
  indexed_paths[utils.normalize(utils.join(notes_dir, 'not_a_note.txt')):lower()] == nil)
check("empty file is not indexed",
  indexed_paths[utils.normalize(utils.join(notes_dir, '00105_note_empty.md')):lower()] == nil)
check("file without frontmatter is not indexed",
  indexed_paths[utils.normalize(utils.join(notes_dir, '00106_note_no_frontmatter.md')):lower()] == nil)
local missing
for _, stem in ipairs({ '00101_note_lf_plain', '00102_note_crlf', '00103_note_bom',
                        '00104_note_no_tags', 'journal_2026-07-24' }) do
  local key = utils.normalize(utils.join(notes_dir, stem .. '.md')):lower()
  if not indexed_paths[key] then missing = missing or stem end
end
check("every well-formed fixture note is indexed", missing == nil, missing)

-- =============================================================================
-- Part C — every entry field equals what the pre-v1.6.2 reader produced
-- =============================================================================

--- The build's per-file logic as it stood before v1.6.2, rebuilt here from
--- vim.fn.readfile + vim.fn.fnamemodify so the new pipeline has something
--- independent to be compared against.
---@param path string
---@return table|nil entry
local function legacy_read_entry(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' or #lines == 0 then return nil end

  local fm, content_start = yaml.parse_frontmatter(lines)
  if not fm then return nil end

  local filename = vim.fn.fnamemodify(path, ':t:r')

  local note_type
  if filename:match('^scratch_') then
    note_type = 'scratch'
  elseif filename:match('^journal_') then
    note_type = 'journal'
  else
    local t = filename:match('^%d+_([a-z]+)_')
    note_type = (t == 'note' or t == 'agg' or t == 'bib') and t or 'other'
  end

  local title = (type(fm.title) == 'string' and fm.title ~= '')
    and fm.title or filename:gsub('_', ' ')

  local tags = {}
  if type(fm.tags) == 'table' then
    for _, t in ipairs(fm.tags) do
      if type(t) == 'string' then tags[#tags + 1] = t:lower() end
    end
  end

  local function any_in_groups(tbl)
    if type(tbl) ~= 'table' then return false end
    for _, grp in ipairs({ 'notes', 'bib', 'journal', 'scratch' }) do
      if type(tbl[grp]) == 'table' and #tbl[grp] > 0 then return true end
    end
    return false
  end

  local parts = {}
  if content_start and content_start <= #lines then
    for i = content_start, #lines do parts[#parts + 1] = lines[i] end
  end
  local body = table.concat(parts, '\n')

  return {
    path          = path,
    filename      = filename,
    note_type     = note_type,
    title         = title,
    tags          = tags,
    body          = body,
    body_lower    = body:lower(),
    mtime         = vim.fn.getftime(path),
    has_citations = any_in_groups(fm.cites) or any_in_groups(fm.cited_by),
  }
end

local compared, mismatch = 0, nil
for _, path in ipairs(globbed) do
  local legacy = legacy_read_entry(path)
  local actual = index.get(path)

  if legacy == nil then
    if actual ~= nil then
      mismatch = mismatch or (path .. ': legacy skipped it, index kept it')
    end
  elseif actual == nil then
    mismatch = mismatch or (path .. ': legacy built an entry, index has none')
  else
    compared = compared + 1
    for _, field in ipairs({ 'filename', 'note_type', 'title', 'body',
                             'body_lower', 'mtime', 'has_citations' }) do
      if legacy[field] ~= actual[field] then
        mismatch = mismatch or string.format('%s: %s %q vs %q',
          vim.fn.fnamemodify(path, ':t'), field,
          tostring(legacy[field]), tostring(actual[field]))
      end
    end
    if #legacy.tags ~= #actual.tags then
      mismatch = mismatch or string.format('%s: tag count %d vs %d',
        vim.fn.fnamemodify(path, ':t'), #legacy.tags, #actual.tags)
    else
      for i = 1, #legacy.tags do
        if legacy.tags[i] ~= actual.tags[i] then
          mismatch = mismatch or string.format('%s: tag %d %q vs %q',
            vim.fn.fnamemodify(path, ':t'), i, legacy.tags[i], actual.tags[i])
        end
      end
    end
  end
end

check("every entry field matches the pre-v1.6.2 reader", mismatch == nil, mismatch)
-- Derived, not hardcoded: the uppercase-extension fixture is indexed on
-- case-insensitive filesystems and not on Linux, and either answer is correct
-- as long as it matches what glob listed.
check("the comparison covered every indexed entry",
  compared >= 5 and compared == #index.get_all(),
  string.format("compared %d, index holds %d", compared, #index.get_all()))

-- =============================================================================
-- Part D — incremental invalidation still works through the new reader
-- =============================================================================

do
  local added = write_note('00107_note_added_later', { 'delta' }, '\r\n')
  index.invalidate(added)
  local entry = index.get(added)
  check("invalidate() indexes a new CRLF note", entry ~= nil)
  check("CRLF note has no stray carriage returns in its body",
    entry ~= nil and not entry.body:find('\r', 1, true),
    entry and string.format('%q', entry.body:sub(1, 40)) or nil)
  check("tags are lowercased through the new reader",
    entry ~= nil and entry.tags[1] == 'delta')

  vim.fn.delete(added)
  index.invalidate(added)
  check("invalidate() drops a deleted note", index.get(added) == nil)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
