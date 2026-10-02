-- =============================================================================
-- pkm.writes — checked writes of note bodies: preview, compare-and-swap,
--              all-or-nothing, history
-- =============================================================================
-- Dependencies : pkm.yaml, pkm.citations, pkm.index, pkm.bufsync,
--                pkm.instances, pkm.timestamp, pkm (config.root_path)
-- Consumed by  : pkm.api (write_notes, write_notes_preview, set_body with opts,
--                file_sha)
--
-- A script that edits a SET of notes — export a snapshot, change the copies,
-- apply them back — needs four things a one-note `set_body` does not give:
--
--   * a preview: the diff of every note before anything is written;
--   * a precondition per note: the file has not changed since it was read
--     (compare-and-swap on the sha256 of its bytes);
--   * all or nothing: every note is checked before the first one is written,
--     and a failure mid-way restores the ones already written;
--   * a history: who wrote what, with the previous text, so it can be undone.
--
-- Without them such a script writes the files itself (`io.open`), and then the
-- citation graph is not reconciled, `last_updated_on` does not move and the
-- write carries no author. Here the write is the same as every other API body
-- write — frontmatter kept, graph reconciled, index invalidated, open buffers
-- reloaded — plus the four above, and `last_updated_on` is stamped.
--
-- An entry gives the new text in one of two forms:
--   body    — the prose after the frontmatter (string or list of lines); the
--             note's frontmatter is kept and one blank line separates them.
--   content — the WHOLE file as the caller edited it (an exported copy). Its
--             frontmatter must be the note's current frontmatter, line for
--             line: the frontmatter is the API's to manage, so a copy that
--             changed it is refused rather than half-applied. Everything after
--             it is the new body, verbatim.
--
-- History: one JSON file per applied batch in `<root>/.pkm-history/`,
-- `{ version, at, by, notes = [{ path (relative to the root), sha_before,
-- sha_after, before }] }` — `before` is the full previous file text, which is
-- what `restore` would need. The newest HISTORY_KEEP batches are kept.
--
-- Public API:
--   sha(path)               → sha256 hex of the file's bytes, or nil
--   apply(entries, opts)    → the batch result (see the function)
-- =============================================================================

local M = {}

local HISTORY_DIR  = '.pkm-history'
local HISTORY_KEEP = 100

-- =============================================================================
-- SECTION: Helpers
-- =============================================================================

local function read_bytes(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local data = f:read('*a')
  f:close()
  return data
end

local function write_bytes(path, data)
  local f, err = io.open(path, 'wb')
  if not f then return false, err end
  f:write(data)
  f:close()
  return true
end

--- sha256 of a file's bytes, exactly as on disk (the hash a caller takes when it
--- exports the note, e.g. `vim.fn.sha256(io.open(p, 'rb'):read('*a'))`).
---@param path string
---@return string|nil
function M.sha(path)
  local data = read_bytes(vim.fn.fnamemodify(path, ':p'))
  if not data then return nil end
  return vim.fn.sha256(data)
end

local function to_lines(content)
  if type(content) == 'table' then return vim.deepcopy(content) end
  local s = tostring(content or ''):gsub('\r\n', '\n')
  local lines = vim.split(s, '\n', { plain = true })
  if #lines > 0 and lines[#lines] == '' then lines[#lines] = nil end
  return lines
end

local function slice(lines, from)
  local out = {}
  for i = from, #lines do out[#out + 1] = lines[i] end
  return out
end

local function text_of(lines)
  if #lines == 0 then return '' end
  return table.concat(lines, '\n') .. '\n'
end

--- The path relative to the vault root, '/'-separated (never an absolute path
--- in vault state); the absolute path when it is outside the root.
local function relative(path)
  local root = ((require('pkm').config or {}).root_path or ''):gsub('\\', '/'):gsub('/+$', '')
  local p = path:gsub('\\', '/')
  if root ~= '' and p:sub(1, #root + 1):lower() == (root .. '/'):lower() then
    return p:sub(#root + 2)
  end
  return p
end

-- =============================================================================
-- SECTION: Planning (pure reads)
-- =============================================================================

--- Read one entry against the disk and work out what it would write.
---@return table plan  { path, changed, diff, sha_before, frontmatter, out_lines, error? }
local function plan_entry(entry)
  local yaml = require('pkm.yaml')
  if type(entry) ~= 'table' or type(entry.path) ~= 'string' or entry.path == '' then
    return { error = 'an entry needs a path' }
  end
  local path = vim.fn.fnamemodify(entry.path, ':p')
  local plan = { path = path }
  if (entry.body == nil) == (entry.content == nil) then
    plan.error = 'give exactly one of body or content'
    return plan
  end

  local raw = read_bytes(path)
  if not raw then plan.error = 'note not found: ' .. path; return plan end
  plan.sha_before = vim.fn.sha256(raw)
  if entry.expected_sha and entry.expected_sha ~= plan.sha_before then
    plan.error = 'the note changed since it was read (sha mismatch)'
    plan.conflict = true
    return plan
  end

  local lines = vim.fn.readfile(path)
  local fm, content_start = yaml.parse_frontmatter(lines)
  if not fm then plan.error = 'note has no frontmatter'; return plan end
  local fm_lines = slice(lines, 1)
  for i = #fm_lines, content_start, -1 do fm_lines[i] = nil end   -- keep 1..content_start-1

  local new_body
  if entry.body ~= nil then
    -- Keep the note's own blank-line run after the frontmatter (at least one),
    -- so a body write does not show up in the diff as whitespace churn.
    local lead = 0
    while lines[content_start + lead] == '' do lead = lead + 1 end
    new_body = {}
    for _ = 1, math.max(lead, 1) do new_body[#new_body + 1] = '' end
    local body, started = to_lines(entry.body), false
    for _, l in ipairs(body) do
      if started or l ~= '' then started = true; new_body[#new_body + 1] = l end
    end
  else
    local copy = to_lines(entry.content)
    local cfm, cstart = yaml.parse_frontmatter(copy)
    if not cfm then plan.error = 'content has no frontmatter'; return plan end
    local same = (cstart == content_start)
    for i = 1, content_start - 1 do
      if not same then break end
      if copy[i] ~= lines[i] then same = false end
    end
    if not same then
      plan.error = "content changes the frontmatter — only the body may change (the frontmatter is the API's)"
      return plan
    end
    new_body = slice(copy, cstart)
  end

  local old_body = slice(lines, content_start)
  local old_text, new_text = text_of(old_body), text_of(new_body)
  plan.changed = old_text ~= new_text
  plan.diff = plan.changed and vim.diff(old_text, new_text, {
    result_type = 'unified', algorithm = 'histogram', ctxlen = 3 }) or ''
  plan.before = raw
  plan.out_lines = fm_lines
  for _, l in ipairs(new_body) do plan.out_lines[#plan.out_lines + 1] = l end
  return plan
end

-- =============================================================================
-- SECTION: Writing
-- =============================================================================

--- Write one planned note: the body, then the graph, then `last_updated_on`.
local function write_one(plan)
  local yaml = require('pkm.yaml')
  if vim.fn.writefile(plan.out_lines, plan.path) ~= 0 then
    error('could not write ' .. plan.path)
  end
  require('pkm.citations').update_references(plan.path)
  local lines = vim.fn.readfile(plan.path)
  local fm, content_start = yaml.parse_frontmatter(lines)
  if fm then
    fm.last_updated_on = require('pkm.timestamp').to_iso8601()
    yaml.save_frontmatter(fm, content_start, plan.path)
  end
  require('pkm.index').invalidate(plan.path)
end

--- Undo one written note: graph first, then the exact bytes. Writing the old
--- bytes back alone would leave the backlinks the new body created on OTHER
--- notes (the restored frontmatter no longer lists them, so the engine would
--- see nothing to remove). So the old BODY goes under the current frontmatter
--- and the engine reconciles — dropping the new edges, restoring the old —
--- and only then is the file put back byte for byte.
local function restore(plan)
  local yaml = require('pkm.yaml')
  local now = vim.fn.readfile(plan.path)
  local _, cs_now = yaml.parse_frontmatter(now)
  local old = to_lines(plan.before)
  local _, cs_old = yaml.parse_frontmatter(old)
  local mixed = {}
  for i = 1, cs_now - 1 do mixed[#mixed + 1] = now[i] end
  for i = cs_old, #old do mixed[#mixed + 1] = old[i] end
  if vim.fn.writefile(mixed, plan.path) == 0 then
    pcall(require('pkm.citations').update_references, plan.path)
  end
  write_bytes(plan.path, plan.before)
  require('pkm.index').invalidate(plan.path)
end

local function record_history(applied, by)
  local root = (require('pkm').config or {}).root_path
  if type(root) ~= 'string' or root == '' then return nil end
  local dir = root .. '/' .. HISTORY_DIR
  vim.fn.mkdir(dir, 'p')
  local stamp = os.date('%Y-%m-%d_%H%M%S')
  local name = string.format('%s_%s.json', stamp, (tostring(by):gsub('[^%w%-]', '')))
  local n = 1
  while vim.fn.filereadable(dir .. '/' .. name) == 1 do
    n = n + 1
    name = string.format('%s_%s_%d.json', stamp, (tostring(by):gsub('[^%w%-]', '')), n)
  end
  local notes = {}
  for _, p in ipairs(applied) do
    notes[#notes + 1] = { path = relative(p.path), sha_before = p.sha_before,
                          sha_after = p.sha_after, before = p.before }
  end
  local ok = write_bytes(dir .. '/' .. name, vim.json.encode({
    version = 1, at = require('pkm.timestamp').to_iso8601(), by = by, notes = notes,
  }))
  if not ok then return nil end
  local files = {}
  for _, f in ipairs(vim.fn.readdir(dir)) do
    if f:match('%.json$') then files[#files + 1] = f end
  end
  table.sort(files)
  for i = 1, #files - HISTORY_KEEP do pcall(vim.fn.delete, dir .. '/' .. files[i]) end
  return HISTORY_DIR .. '/' .. name
end

--- Apply (or preview) a batch of body writes.
---
--- Every entry is read and checked first — the note exists and has a
--- frontmatter, `expected_sha` matches, a `content` copy kept the frontmatter —
--- and then, unless `dry_run`, none of the notes may be open with unsaved
--- changes here or in another registered Neovim session. Any failure stops the
--- batch before the first write (`ok = false`, `written = 0`). A failure while
--- writing restores the notes already written (`rolled_back = true`).
---@param entries table[]  { path, body? | content?, expected_sha? }
---@param opts table|nil   { dry_run?, by? (default 'claude'), history? (default true), timeout? }
---@return table  { ok, dry_run, by, written, unchanged, notes = [{ path, changed, diff,
---                 sha_before, sha_after?, error? }], history?, error?, rolled_back? }
function M.apply(entries, opts)
  opts = opts or {}
  local by = opts.by or 'claude'
  local res = { ok = false, dry_run = opts.dry_run == true, by = by, written = 0, unchanged = 0, notes = {} }
  if type(entries) ~= 'table' or #entries == 0 then
    res.error = 'no entries'
    return res
  end

  -- 1. Plan every entry (reads only).
  local plans, seen, failed = {}, {}, nil
  for i, e in ipairs(entries) do
    local p = plan_entry(e)
    if p.path then
      local k = p.path:gsub('\\', '/'):lower()
      if seen[k] and not p.error then p.error = 'the same note appears twice in the batch' end
      seen[k] = true
    end
    plans[i] = p
    res.notes[i] = { path = p.path, changed = p.changed, diff = p.diff,
                     sha_before = p.sha_before, error = p.error }
    if p.error and not failed then failed = p end
  end
  if failed then
    res.error = string.format('%s: %s', tostring(failed.path or '?'), failed.error)
    return res
  end
  for _, p in ipairs(plans) do
    if not p.changed then res.unchanged = res.unchanged + 1 end
  end
  if res.dry_run then
    res.ok = true
    return res
  end

  -- 2. No note may sit behind unsaved edits — here or in another session.
  local paths = {}
  for _, p in ipairs(plans) do
    if p.changed then
      local bufnr = require('pkm.bufsync').buffer_for(p.path)
      if bufnr and vim.bo[bufnr].modified then
        res.error = 'the note has unsaved changes — save it first: ' .. p.path
        return res
      end
      paths[#paths + 1] = p.path
    end
  end
  if #paths == 0 then
    res.ok = true
    return res
  end
  local blocked = require('pkm.instances').blocking(paths, { timeout = opts.timeout })
  if blocked then
    res.error = blocked
    return res
  end

  -- 3. Write them all; on any failure, put back what was already written.
  local applied = {}
  for i, p in ipairs(plans) do
    if p.changed then
      local ok, err = pcall(write_one, p)
      if not ok then
        for _, done in ipairs(applied) do restore(done) end
        -- The failing note may be half-written (the body landed, the graph
        -- step failed): put it back too — unless nothing of it was written.
        if read_bytes(p.path) ~= p.before then restore(p) end
        require('pkm.bufsync').reload(paths)
        res.notes[i].error = tostring(err)
        res.error = string.format('%s: write failed (%s); every note was restored', p.path, tostring(err))
        res.rolled_back = true
        return res
      end
      p.sha_after = M.sha(p.path)
      res.notes[i].sha_after = p.sha_after
      applied[#applied + 1] = p
    end
  end
  require('pkm.bufsync').reload(paths)
  res.written = #applied
  res.ok = true

  -- 4. History (who, when, and the text it replaced).
  if opts.history ~= false then
    res.history = record_history(applied, by)
  end
  return res
end

return M
