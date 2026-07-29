-- =============================================================================
-- pkm.check — A read-only audit of the vault's integrity
-- =============================================================================
-- Dependencies : pkm.utils, pkm.yaml, pkm.citations, pkm.vault, pkm (config)
-- Consumed by  : pkm.commands (:PKMCheck)
--
-- Pure and read-only: `run` reads every note, cross-checks the citation graph,
-- the numbering and the cross-vault references, and returns a flat list of
-- findings. It writes nothing and opens nothing — the command formats.
--
-- The whole design rule of this module is *no false positive*. A checker that
-- cries wolf is worse than none, because the reader learns to ignore it, so
-- every check here reports only what is provably wrong given the vault as it is
-- on disk: a citation with no note behind it, a backlink the other side does not
-- return, two notes fighting over one number, a reference to a vault that is not
-- registered. Anything it is not certain about, it stays silent on.
--
-- A finding:
--   { kind     : string   short machine label, e.g. 'dangling-citation'
--     severity : 'error' | 'warning'
--     path      : string|nil  the note the problem is in, when there is one
--     message   : string   one line, human-readable }
--
-- Public API:
--   run() → finding[]   every problem found, errors before warnings
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

local function get_config()
  return require('pkm').config or {}
end

-- =============================================================================
-- SECTION: Collecting the corpus
-- =============================================================================

--- The identifiers a note cites or is cited by, flattened across the four
--- groups. Returns nil when the field is present but not the grouped shape —
--- that malformation is itself a finding, raised by check_frontmatter.
---@param field any  fm.cites or fm.cited_by
---@return string[]|nil ids  nil signals "malformed", {} signals "none"
local function ids_of(field)
  if field == nil then return {} end
  if type(field) ~= 'table' then return nil end

  local ids = {}
  local grouped = false
  for _, group in ipairs({ 'notes', 'bib', 'journal', 'scratch' }) do
    if field[group] ~= nil then
      grouped = true
      if type(field[group]) ~= 'table' then return nil end
      for _, e in ipairs(field[group]) do
        if type(e) == 'table' and type(e.identifier) == 'string' then
          ids[#ids + 1] = e.identifier
        end
      end
    end
  end
  -- An empty table is a valid "no citations"; a non-empty one with no known
  -- group is malformed.
  if not grouped and next(field) ~= nil then return nil end
  return ids
end

--- Read every note under the active root into records the checks share.
--- One file read per note; the body lines are kept for the reference scan.
---@return table[] records  { path, filename, identifier, note_type, fm_ok,
---                           cites, cited_by, malformed, number, body }
local function collect()
  local cfg = get_config()
  local citations = require('pkm.citations')
  local yaml = require('pkm.yaml')

  local records = {}
  for _, folder in ipairs({ cfg.folders and cfg.folders.consolidated,
                            cfg.folders and cfg.folders.journal,
                            cfg.folders and cfg.folders.scratchpad }) do
    if folder then
      local dir = utils.join(cfg.root_path, folder)
      for _, path in ipairs(vim.fn.glob(dir .. utils.sep .. '*.md', false, true)) do
        local lines = vim.fn.readfile(path)
        local fm, content_start = yaml.parse_frontmatter(lines)
        local item_type, identifier = citations.get_note_type_and_id(path)

        local rec = {
          path       = path,
          filename   = vim.fn.fnamemodify(path, ':t:r'),
          note_type  = item_type,
          identifier = identifier,
          fm_ok      = fm ~= nil,
          number     = tonumber((vim.fn.fnamemodify(path, ':t'):match('^(%d+)_'))),
        }

        if fm then
          rec.cites    = ids_of(fm.cites)
          rec.cited_by = ids_of(fm.cited_by)
          rec.malformed = (rec.cites == nil) or (rec.cited_by == nil)
        end

        local body = {}
        if content_start then
          for i = content_start, #lines do body[#body + 1] = lines[i] end
        end
        rec.body = body

        records[#records + 1] = rec
      end
    end
  end
  return records
end

-- =============================================================================
-- SECTION: The checks
-- =============================================================================

--- Frontmatter present and its citation fields well-shaped.
local function check_frontmatter(records, out)
  for _, r in ipairs(records) do
    if not r.fm_ok then
      out[#out + 1] = { kind = 'no-frontmatter', severity = 'error', path = r.path,
        message = 'no readable frontmatter' }
    elseif r.malformed then
      out[#out + 1] = { kind = 'malformed-citations', severity = 'error', path = r.path,
        message = 'cites/cited_by is present but not the grouped {notes,bib,journal,scratch} shape' }
    end
  end
end

--- Every citation identifier resolves to a note that exists in this vault.
local function check_dangling(records, out)
  local exists = {}
  for _, r in ipairs(records) do
    if r.identifier then exists[r.identifier] = true end
  end

  for _, r in ipairs(records) do
    for _, field in ipairs({ 'cites', 'cited_by' }) do
      for _, id in ipairs(r[field] or {}) do
        if not exists[id] then
          out[#out + 1] = { kind = 'dangling-citation', severity = 'error', path = r.path,
            message = string.format("%s names '%s', which no note in this vault matches",
              field, id) }
        end
      end
    end
  end
end

--- If A cites B, then B is cited_by A — and the reverse. An asymmetry is a real
--- defect: the citation graph is bidirectional by construction, so a one-sided
--- edge means an edit or a bug left the two sides disagreeing.
local function check_symmetry(records, out)
  local by_id = {}
  for _, r in ipairs(records) do
    if r.identifier then by_id[r.identifier] = r end
  end

  local function has(list, id)
    for _, x in ipairs(list or {}) do if x == id then return true end end
    return false
  end

  for _, r in ipairs(records) do
    if r.identifier then
      for _, tgt in ipairs(r.cites or {}) do
        local other = by_id[tgt]
        -- A dangling target is already reported; only a resolvable one can be
        -- checked for the return edge, or this would double-count.
        if other and not has(other.cited_by, r.identifier) then
          out[#out + 1] = { kind = 'asymmetric-citation', severity = 'error', path = r.path,
            message = string.format("cites '%s', but %s does not list it back in cited_by",
              tgt, other.filename) }
        end
      end
      for _, src in ipairs(r.cited_by or {}) do
        local other = by_id[src]
        if other and not has(other.cites, r.identifier) then
          out[#out + 1] = { kind = 'asymmetric-citation', severity = 'error', path = r.path,
            message = string.format("is cited_by '%s', but %s does not cite it", src, other.filename) }
        end
      end
    end
  end
end

--- No two consolidated notes share a number.
local function check_numbering(records, out)
  local seen = {}
  for _, r in ipairs(records) do
    -- Only numbered notes: journal/scratch carry timestamps, not the shared
    -- counter, so they never collide on a number.
    if r.number and (r.note_type == 'note' or r.note_type == 'bib') then
      if seen[r.number] then
        out[#out + 1] = { kind = 'number-collision', severity = 'error', path = r.path,
          message = string.format('number %04d is also used by %s', r.number, seen[r.number]) }
      else
        seen[r.number] = r.filename
      end
    end
  end
end

--- Cross-vault references naming a vault that is not registered.
--- `[Vault::type{id}]` is inert by construction (doc/CONVENTIONS.md), so it is
--- never in `cites` and nothing else would ever notice a wrong vault name. This
--- is the one place it is read at all. Only runs when a registry exists; without
--- one there are no vault names to check against.
local function check_cross_vault(records, out)
  local vault = require('pkm.vault')
  local registered = vault.list()
  if #registered == 0 then return end   -- no registry: nothing to check against

  local known = {}
  for _, v in ipairs(registered) do known[v.name:lower()] = true end

  -- Names that once existed, from the rename history, so the message can say
  -- "renamed" rather than "unknown" — the mitigation for the no-aliases rule.
  local renamed = {}
  for _, h in ipairs(vault.history()) do
    if h.from then renamed[tostring(h.from):lower()] = h.to end
  end

  -- `[Name::type{id}]`: the name is anything up to `::`, allowing spaces.
  local pattern = '%[([^:%[%]]+)::(%w+)%{([^%}]+)%}%]'

  for _, r in ipairs(records) do
    for _, line in ipairs(r.body) do
      for name in line:gmatch(pattern) do
        local key = name:lower()
        if not known[key] then
          if renamed[key] then
            out[#out + 1] = { kind = 'renamed-vault-reference', severity = 'warning', path = r.path,
              message = string.format("references vault '%s', renamed to '%s' — the name may now "
                .. 'point elsewhere', name, renamed[key]) }
          else
            out[#out + 1] = { kind = 'unknown-vault-reference', severity = 'warning', path = r.path,
              message = string.format("references vault '%s', which is not registered", name) }
          end
        end
      end
    end
  end
end

--- Notes stranded in `Unregistered/`: a vault was taken out of the registry and
--- its folder is waiting to be adopted, split or merged. Reported once per note
--- so the count is honest, not once for the folder.
local function check_unregistered(out)
  local vault = require('pkm.vault')
  local dir = vault.unregistered_dir()
  if not dir or vim.fn.isdirectory(dir) == 0 then return end

  local md = vim.fn.glob(dir .. '/**/*.md', false, true)
  if #md > 0 then
    out[#out + 1] = { kind = 'unregistered-notes', severity = 'warning', path = dir,
      message = string.format('%d note%s wait in Unregistered/ — adopt, split or merge the folder',
        #md, #md == 1 and '' or 's') }
  end
end

-- =============================================================================
-- SECTION: Entry point
-- =============================================================================

--- Audit the active vault and return every problem found, errors first.
---@return table[] findings
function M.run()
  local records = collect()
  local out = {}

  check_frontmatter(records, out)
  check_dangling(records, out)
  check_symmetry(records, out)
  check_numbering(records, out)
  check_cross_vault(records, out)
  check_unregistered(out)

  -- Errors before warnings, and — since table.sort is not stable — the original
  -- discovery order kept within a severity, so the same vault always reports in
  -- the same order.
  local rank = { error = 1, warning = 2 }
  for i, f in ipairs(out) do f._i = i end
  table.sort(out, function(a, b)
    if rank[a.severity] ~= rank[b.severity] then return rank[a.severity] < rank[b.severity] end
    return a._i < b._i
  end)
  for _, f in ipairs(out) do f._i = nil end
  return out
end

return M
