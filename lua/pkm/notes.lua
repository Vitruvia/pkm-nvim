-- =============================================================================
-- pkm.notes — Note creation, conversion, promotion, and navigation
-- =============================================================================
-- Dependencies : pkm.yaml, pkm.utils, pkm.timestamp, pkm.citations (lazy)
-- Consumed by  : pkm.commands, pkm.keymaps
--
-- Public API:
--   setup(user_config)                        → Initialize with resolved PKM config
--   create_new_note(note_type?, opts?)        → Create consolidated note (prompts if nil);
--                                               opts.tags seeds the frontmatter tags
--   create_relative_note(note_type?)          → Create a note inheriting the current
--                                               note's tags, so it lands in the same views
--   create_scratchpad()                       → Create timestamped scratchpad note
--   promote_note()                            → Promote scratchpad to consolidated or journal
--   do_convert(current_path, current_type, target) → Perform note type conversion
--   convert_note()                            → Normalize current note to its folder's format
--   change_note_type()                        → Change type of consolidated note and rename file
--   transpose_note()                          → Move note to different folder and convert
--   rename_note()                             → Prompt for new name and rename current note
--   link_to_note()                            → Insert [[wiki-link]] at cursor
--   follow_link()                             → Open note linked under cursor
--   show_backlinks()                          → Show all notes linking to current note
--   set_title()  → prompt for title, write to current buffer frontmatter (buffer-only)
--   import_note()                             → Import external file into PKM structure
-- =============================================================================
local M = {}

local utils = require('pkm.utils')
local config = {}
local yaml = nil
local timestamp = nil

-- =============================================================================
-- SECTION: Setup
-- =============================================================================
---@param user_config table Resolved PKM config from pkm.config.resolve()
function M.setup(user_config)
  config = user_config
  yaml = require('pkm.yaml')
  timestamp = require('pkm.timestamp')
end

-- =============================================================================
-- SECTION: File naming helpers
-- =============================================================================
--- Get next available note number, skipping any numbers used by trashed notes.
--- Gaps in numbering are intentional: a trashed note retains its number so
--- that restoration never conflicts with a newer note.
local function get_next_note_number()
  local consolidated_path = utils.join(config.root_path, config.folders.consolidated)
  local files = vim.fn.glob(consolidated_path .. utils.sep .. "*.md", false, true)

  local max_num = 0
  for _, file in ipairs(files) do
    local basename = vim.fn.fnamemodify(file, ":t:r")
    local num = basename:match("^(%d+)_")
    if num then
      max_num = math.max(max_num, tonumber(num))
    end
  end

  -- Also check the trash manifest so a restored note never shares a number
  -- with a note created after it was trashed.
  local ok, trash = pcall(require, 'pkm.trash')
  if ok then
    for _, entry in ipairs(trash.list()) do
      local basename = vim.fn.fnamemodify(entry.original_path, ':t:r')
      local num = basename:match('^(%d+)_')
      if num then
        max_num = math.max(max_num, tonumber(num))
      end
    end
  end

  return max_num + 1
end

--- Sanitize title for filename
--- @param title string Title to sanitize
--- @return string Safe filename part
local function sanitize_title(title)
  if not title or title == "" then
    return "unnamed"
  end
  
  -- Remove or replace problematic characters
  local safe = title
    :gsub("%s+", "_")                    -- spaces to underscores
    :gsub('[<>:"/\\|?*]', "")            -- remove Windows/Unix forbidden chars
    :gsub("_+", "_")                     -- collapse multiple underscores
    :gsub("^_", "")                      -- remove leading underscore
    :gsub("_$", "")                      -- remove trailing underscore
  
  if safe == "" then
    return "unnamed"
  end
  
  return safe
end

-- =============================================================================
-- SECTION: Frontmatter editing (buffer-only)
-- =============================================================================

--- Set the current buffer's frontmatter title.
--- Buffer-only — no disk write. BufWritePre/BufWritePost handle persistence.
--- Must NOT call index.invalidate: no disk write occurred; the index re-reads
--- correctly when the user saves.
---
--- Interactive and programmatic are the one command: with `new_title` given
--- (`:PKMNote settitle My Note`) it writes it straight; without one it prompts,
--- seeded with the current title. `new_title` is taken as-is, so a script can
--- set any string, including an empty one.
---@param new_title string|nil  When nil, prompt; otherwise use verbatim
function M.set_title(new_title)
  local filepath  = vim.fn.expand('%:p')
  local norm_path = filepath:gsub('\\', '/')
  local norm_root = config.root_path:gsub('\\', '/')
  if filepath == '' or not norm_path:lower():find(norm_root:lower(), 1, true) then
    vim.notify('[pkm] not a PKM note', vim.log.levels.WARN)
    return
  end

  local yaml_m = require('pkm.yaml')
  local lines   = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local fm, content_start = yaml_m.parse_frontmatter(lines)
  if not fm then
    vim.notify('[pkm] no frontmatter found', vim.log.levels.WARN)
    return
  end

  if new_title == nil then
    local current = type(fm.title) == 'string' and fm.title or ''
    vim.fn.inputsave()
    new_title = vim.fn.input('Title: ', current)
    vim.fn.inputrestore()
    if new_title == nil then return end   -- Esc / cancelled
  end

  fm.title = new_title
  yaml_m.save_frontmatter(fm, content_start)   -- Case A: buffer-only, no disk write
  vim.notify('[pkm] title updated — save to persist', vim.log.levels.INFO)
end

-- =============================================================================
-- SECTION: Note creation
-- =============================================================================
--- Create a new consolidated note in the configured consolidated folder.
--- Prompts for type if not provided, then for title. Handles bib-specific
--- fields (source_author, source_type) when type is "bib".
---
--- The new note is opened in a real editing window, chosen by `opts.where`.
--- **This function owns that guard**, rather than each caller: it is the one
--- that opens a buffer, and a caller that forgets gets E1513 from a panel with
--- `winfixbuf` set — which is exactly what happened to note creation from the
--- sidebar.
---@param note_type string|nil "note", "agg", or "bib" — prompts if nil
---@param opts table|nil  { tags = string[] } seeds the new note's frontmatter
---                       tags; used by create_relative_note()
---                       { where = nil|'left'|'right'|integer } which window to
---                       open it in — see `utils.focus_editing_win`
---                       { title = string } supplied title; when present, the
---                       title prompt is skipped (`:PKMNote new … title=`)
---                       { by = string } agent author; marks the note
---                       NNNN_type_By<Author>_slug and records the author
---@return string|nil filepath Absolute path of created note, or nil on cancel
function M.create_new_note(note_type, opts)
  opts = opts or {}

  if note_type == "" then
    note_type = nil
  end

  -- If no type provided, prompt for it
  if not note_type then
    vim.ui.select(
      {"note", "agg", "bib"},
      {
        prompt = "Select note type:",
        format_item = function(item)
          if item == "note" then return "Regular Note"
          elseif item == "agg" then return "Aggregate/Collection"
          elseif item == "bib" then return "Bibliography Entry"
          end
        end
      },
      function(selected)
        if selected then
          M.create_new_note(selected, opts) -- SIMPLIFIED recursive call
        else
          vim.notify("Note creation cancelled", vim.log.levels.INFO)
        end
      end
    )
    return nil
  end
  
  -- Validate type
  if not (note_type == "agg" or note_type == "note" or note_type == "bib") then
    vim.notify("Invalid note type. Use: agg, note, or bib", vim.log.levels.ERROR)
    return nil
  end
  
  -- Get note title. A title supplied by the caller (`title=` on the command)
  -- skips the prompt entirely, so `:PKMNote new note title=Foo` creates without
  -- interaction; an explicit empty title is still "supplied" and means unnamed.
  local title = opts.title
  if title == nil then
    vim.fn.inputsave()
    -- SIMPLIFIED: Always allow unnamed notes
    title = vim.fn.input("Note title (leave empty for unnamed): ")
    vim.fn.inputrestore()

    -- If user cancels with <Esc>, title will be nil
    if title == nil then
      vim.notify("Note creation cancelled", vim.log.levels.INFO)
      return nil
    end
  end
  
  -- Generate filename (the rest of the function is the same)
  local note_number = get_next_note_number()
  local safe_title  = sanitize_title(title)

  -- Agent authorship, marked in the name itself: a note written by an agent
  -- becomes NNNN_type_By<Author>_slug. The marker travels with the file — it
  -- survives a copy, a move between vaults, and a manual rename that keeps the
  -- prefix — which is why the deletion guard reads it from the name rather than
  -- from frontmatter that a careless edit could drop.
  local author_marker
  if type(opts.by) == 'string' and opts.by ~= '' then
    author_marker = 'By' .. opts.by:sub(1, 1):upper() .. opts.by:sub(2)
    safe_title    = author_marker .. '_' .. safe_title
  end

  local filename = string.format("%04d_%s_%s.md", note_number, note_type, safe_title)

  local consolidated_path = utils.join(config.root_path, config.folders.consolidated)
  utils.ensure_dir(consolidated_path)
  
  local filepath = utils.join(consolidated_path, filename)
  
  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("File already exists: " .. filename, vim.log.levels.ERROR)
    return nil
  end
  
  local fm_type = (note_type == "bib") and "bibliography"
             or (note_type == "agg") and "agg"
             or "note"
  local frontmatter_data = {
    title = title ~= "" and title or "Unnamed Note",
  }
  -- An agent-authored note records the agent as its author, so who wrote it is
  -- legible in the note as well as in its name.
  if opts.by and opts.by ~= '' then
    frontmatter_data.author = opts.by:sub(1, 1):upper() .. opts.by:sub(2)
  end

  -- Seeded tags (relative note), plus the by-claude authorship tag on an
  -- agent-created note, so authorship is queryable vault-wide
  -- (AGENT_PROTOCOL.md § 7) — matching the headless write_new_note, so the
  -- interactive and programmatic create paths cannot drift. Both go through
  -- pkm.tags.plan, so the result is normalised and de-duplicated.
  local seed_tags = {}
  if type(opts.tags) == "table" then vim.list_extend(seed_tags, opts.tags) end
  if type(opts.by) == "string" and opts.by ~= '' then
    seed_tags[#seed_tags + 1] = 'by-claude'
  end
  if #seed_tags > 0 then
    local seeded = require('pkm.tags').plan({}, { add = seed_tags })
    if #seeded > 0 then frontmatter_data.tags = seeded end
  end

  -- A bib note's author and source are prompted only on the interactive path.
  -- A title supplied by the caller means "do not interact", so the programmatic
  -- form stays promptless throughout; those fields are then left for frontmatter
  -- editing. (Their own named arguments are a later phase's addition.)
  if note_type == "bib" and opts.title == nil then
    vim.fn.inputsave()
    local author = vim.fn.input("Author: ")
    vim.fn.inputrestore()
    if author ~= "" then
      frontmatter_data.source_author = author
    end

    vim.fn.inputsave()
    local source_type = vim.fn.input("Source type [book]: ", "book")
    vim.fn.inputrestore()
    frontmatter_data.source_type = source_type
  end
  
  local frontmatter_lines = yaml.create_frontmatter(fm_type, frontmatter_data)
  
  -- Add a blank line for content
  table.insert(frontmatter_lines, "")
  
  vim.fn.writefile(frontmatter_lines, filepath)
  require('pkm.index').invalidate(filepath)
  -- Land in a window that may hold a buffer before opening: called from a
  -- panel, `edit` would fail on winfixbuf.
  utils.focus_editing_win(opts.where)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))

  vim.cmd("normal! G")
  
  vim.notify("Created: " .. filename, vim.log.levels.INFO)
  return filepath
end

--- Normalise a body argument (a string, a list of lines, or nil) to a list of
--- lines, so callers may pass either form.
---@param content string|string[]|nil
---@return string[]
local function to_lines(content)
  local out = {}
  if type(content) == 'table' then
    for _, l in ipairs(content) do out[#out + 1] = tostring(l) end
  elseif type(content) == 'string' then
    for l in (content .. '\n'):gmatch('(.-)\n') do out[#out + 1] = l end
  end
  return out
end

--- Write a new consolidated note to disk with no UI whatsoever.
---
--- The headless-safe core beneath the interactive `create_new_note` and the one
--- `pkm.api` calls: it allocates the next number, builds schema-correct
--- frontmatter, writes the file, and invalidates the index — no prompt, no
--- buffer opened, no notice. The type is required (there is no picker); a nil
--- title means an unnamed note. An agent author (`by`) is stamped three ways per
--- `doc/AGENT_PROTOCOL.md` § 7: the `By<Author>` filename marker, the `author`
--- frontmatter field, and the queryable `by-claude` tag.
---
--- (Follow-up: migrate `create_new_note` to delegate its write here, so the
--- interactive `by=` path also stamps the by-claude tag and the two paths cannot
--- drift. Deferred only to avoid an anchor-fragile edit this pass.)
---@param note_type string  "note" | "agg" | "bib"
---@param opts table|nil  { title?, by?, tags?, body?, source_author?, source_type? }
---                       `body` is a string or list of lines; the note is born
---                       populated, and citation tokens in it are reconciled.
---@return string|nil filepath  Absolute path, or nil on error
---@return string|nil err
---@return table|nil meta  { number, filename, title, tags, author }
function M.write_new_note(note_type, opts)
  opts = opts or {}
  if not (note_type == "agg" or note_type == "note" or note_type == "bib") then
    return nil, "invalid note type: use agg, note, or bib"
  end

  local title       = opts.title or ""
  local note_number = get_next_note_number()
  local safe_title  = sanitize_title(title)

  local author
  if type(opts.by) == 'string' and opts.by ~= '' then
    author     = opts.by:sub(1, 1):upper() .. opts.by:sub(2)
    safe_title = 'By' .. author .. '_' .. safe_title
  end

  local filename = string.format("%04d_%s_%s.md", note_number, note_type, safe_title)
  local consolidated_path = utils.join(config.root_path, config.folders.consolidated)
  utils.ensure_dir(consolidated_path)
  local filepath = utils.join(consolidated_path, filename)
  if vim.fn.filereadable(filepath) == 1 then
    return nil, "file already exists: " .. filename
  end

  local fm_type = (note_type == "bib") and "bibliography"
    or (note_type == "agg") and "agg"
    or "note"
  local frontmatter_data = { title = title ~= "" and title or "Unnamed Note" }
  if author then frontmatter_data.author = author end

  -- Seeded tags, plus the by-claude authorship tag on an agent-created note, so
  -- authorship is queryable vault-wide, not only legible in the filename. Both
  -- go through pkm.tags.plan, so the result is normalised and de-duplicated.
  local seed = {}
  if type(opts.tags) == "table" then vim.list_extend(seed, opts.tags) end
  if author then seed[#seed + 1] = 'by-claude' end
  if #seed > 0 then
    local planned = require('pkm.tags').plan({}, { add = seed })
    if #planned > 0 then frontmatter_data.tags = planned end
  end

  if type(opts.source_author) == 'string' and opts.source_author ~= '' then
    frontmatter_data.source_author = opts.source_author
  end
  if type(opts.source_type) == 'string' and opts.source_type ~= '' then
    frontmatter_data.source_type = opts.source_type
  end

  local frontmatter_lines = yaml.create_frontmatter(fm_type, frontmatter_data)
  table.insert(frontmatter_lines, "")

  -- Optional body, so a note is born populated rather than hollow. Any citation
  -- tokens in it are reconciled into the graph after the write, so a note
  -- created citing others lands with cites/cited_by already correct.
  local body_lines = to_lines(opts.body)
  for _, l in ipairs(body_lines) do frontmatter_lines[#frontmatter_lines + 1] = l end

  vim.fn.writefile(frontmatter_lines, filepath)
  require('pkm.index').invalidate(filepath)
  if #body_lines > 0 then
    pcall(function() require('pkm.citations').update_references(filepath) end)
  end

  return filepath, nil, {
    number   = note_number,
    filename = filename,
    title    = frontmatter_data.title,
    tags     = frontmatter_data.tags or {},
    author   = author,
  }
end

--- Write a note's body (everything after the frontmatter), preserving the
--- frontmatter exactly. The prose is free; the structural parts are not — so
--- after the write the citation graph is reconciled to the new body's tokens,
--- keeping cites/cited_by auditable rather than letting a raw edit desync them.
---
--- Like the other write paths, it refuses to run behind an unsaved buffer and
--- reloads an open buffer afterwards. `mode` is `'replace'` (default — swap the
--- whole body) or `'append'` (add after the existing body).
---@param path string  Absolute note path
---@param content string|string[]  the body, a string or a list of lines
---@param opts table|nil  { mode?: 'replace'|'append' }
---@return boolean ok
---@return string|nil err
function M.write_body(path, content, opts)
  opts = opts or {}
  path = vim.fn.fnamemodify(path, ':p')
  if vim.fn.filereadable(path) == 0 then
    return false, 'note not found: ' .. path
  end

  local bufsync = require('pkm.bufsync')
  local bufnr   = bufsync.buffer_for(path)
  if bufnr and vim.bo[bufnr].modified then
    return false, 'the note has unsaved changes — save it first'
  end

  local lines = vim.fn.readfile(path)
  local fm, content_start = yaml.parse_frontmatter(lines)
  if not fm then return false, 'note has no frontmatter' end

  local out = {}
  if opts.mode == 'append' then
    for _, l in ipairs(lines) do out[#out + 1] = l end
    if #out > 0 and out[#out]:match('%S') then out[#out + 1] = '' end
  else
    for i = 1, content_start - 1 do out[#out + 1] = lines[i] end  -- frontmatter block
    out[#out + 1] = ''                                            -- one blank separator
  end
  for _, l in ipairs(to_lines(content)) do out[#out + 1] = l end

  vim.fn.writefile(out, path)
  -- Keep the graph consistent with whatever citation tokens the new body holds:
  -- a replaced body that dropped a token loses that cite (and its backlink), a
  -- body that gained one registers it — the invariant :PKMCheck asserts.
  pcall(function() require('pkm.citations').update_references(path) end)
  require('pkm.index').invalidate(path)
  bufsync.reload({ path })
  return true
end

--- Write into a *named section* of a note — placement-aware body writing — while
--- preserving the frontmatter and reconciling the citation graph. The section is
--- located by its heading text (case-insensitive), and its extent runs to the
--- next heading of the same or a shallower level (headings inside code fences do
--- not count). `mode` is `'append'` (default — add at the end of the section) or
--- `'replace'` (swap the section's body, keeping the heading). Refuses behind an
--- unsaved buffer and reloads an open buffer afterwards.
---@param path string  Absolute note path
---@param heading string  the section's heading text, without the leading #'s
---@param content string|string[]
---@param opts table|nil  { mode?: 'append'|'replace' }
---@return boolean ok
---@return string|nil err
function M.write_section(path, heading, content, opts)
  opts = opts or {}
  path = vim.fn.fnamemodify(path, ':p')
  if vim.fn.filereadable(path) == 0 then
    return false, 'note not found: ' .. path
  end

  local bufsync = require('pkm.bufsync')
  local bufnr   = bufsync.buffer_for(path)
  if bufnr and vim.bo[bufnr].modified then
    return false, 'the note has unsaved changes — save it first'
  end

  local lines = vim.fn.readfile(path)
  local heads = require('pkm.markdown').scan_headings(lines)

  local want = vim.trim(tostring(heading)):lower()
  local idx, head
  for i, h in ipairs(heads) do
    local text = lines[h.lnum]:match('^%s*#+%s*(.-)%s*$') or ''
    if text:lower() == want then
      idx, head = i, h
      break
    end
  end
  if not head then
    return false, string.format("no section titled '%s'", heading)
  end

  -- The section runs to the line before the next heading at the same or a
  -- shallower level, or to end of file.
  local sec_end = #lines
  for i = idx + 1, #heads do
    if heads[i].level <= head.level then
      sec_end = heads[i].lnum - 1
      break
    end
  end

  local body = to_lines(content)
  local out  = {}

  if opts.mode == 'replace' then
    for i = 1, head.lnum do out[#out + 1] = lines[i] end   -- through the heading
    out[#out + 1] = ''
    for _, l in ipairs(body) do out[#out + 1] = l end
    if sec_end < #lines then out[#out + 1] = '' end
    for i = sec_end + 1, #lines do out[#out + 1] = lines[i] end
  else
    -- append after the last non-blank line of the section
    local last = head.lnum
    for i = head.lnum, sec_end do if lines[i]:match('%S') then last = i end end
    for i = 1, last do out[#out + 1] = lines[i] end
    out[#out + 1] = ''
    for _, l in ipairs(body) do out[#out + 1] = l end
    if lines[last + 1] and lines[last + 1]:match('%S') then out[#out + 1] = '' end
    for i = last + 1, #lines do out[#out + 1] = lines[i] end
  end

  vim.fn.writefile(out, path)
  pcall(function() require('pkm.citations').update_references(path) end)
  require('pkm.index').invalidate(path)
  bufsync.reload({ path })
  return true
end

--- Append a *marked comment* to a note — the safe way to write into a note that
--- is not the assistant's own (`doc/AGENT_PROTOCOL.md` § 7). Unlike write_body,
--- the marker is not optional: the block begins with `By <Author>: `, so an
--- addition to someone else's note is always attributable, and it lands at a
--- boundary — the end of a named section (`opts.heading`) or the end of the note
--- — never woven inline. It writes only the assistant's own block and never
--- touches what the user wrote; frontmatter is preserved and the graph reconciled
--- (it delegates to write_section / write_body, so it also refuses behind an
--- unsaved buffer).
---@param path string  Absolute note path
---@param content string|string[]  the comment body
---@param opts table|nil  { heading?: string, by?: string }
---@return boolean ok
---@return string|nil err
function M.annotate(path, content, opts)
  opts = opts or {}
  local by     = (type(opts.by) == 'string' and opts.by ~= '') and opts.by or 'Claude'
  local author = by:sub(1, 1):upper() .. by:sub(2)

  local lines = to_lines(content)
  local has_text = false
  for _, l in ipairs(lines) do if l:match('%S') then has_text = true break end end
  if not has_text then return false, 'no content to add' end

  -- The block begins with the marker; the boundary blank lines that write_section
  -- and write_body insert around an append keep it a distinct, attributable block.
  local marked = { string.format('By %s: %s', author, lines[1]) }
  for i = 2, #lines do marked[#marked + 1] = lines[i] end

  if type(opts.heading) == 'string' and opts.heading ~= '' then
    return M.write_section(path, opts.heading, marked, { mode = 'append' })
  end
  return M.write_body(path, marked, { mode = 'append' })
end

--- Merge one note into another — the lifecycle write behind duplicate resolution.
--- `absorbed` is folded into `survivor`: its body is appended, its citation graph
--- is **redirected** onto the survivor (every note that cited the absorbed note now
--- cites the survivor; everything the absorbed note cited, the survivor now cites
--- via the copied body), its topical tags are unioned in, and it is then trashed
--- through the deletion guard. Because trashing preserves backlinks for restore
--- (`trash.trash_note`), the graph is redirected *first*, so no dangling edge is
--- left behind. **Both notes must be assistant-authored** — the survivor's body is
--- rewritten and the absorbed note is deleted, neither of which is done to a human's
--- note here.
---@param survivor_path string  the note that remains
---@param absorbed_path string  the note folded in and trashed
---@param opts table|nil  { heading?: string }  place the absorbed body under a heading
---@return string|nil survivor  the survivor path, or nil on error
---@return string|nil err
---@return table|nil meta  { redirected, absorbed_title }
function M.merge_notes(survivor_path, absorbed_path, opts)
  opts = opts or {}
  survivor_path = vim.fn.fnamemodify(survivor_path, ':p')
  absorbed_path = vim.fn.fnamemodify(absorbed_path, ':p')

  local function same(a, b)
    return vim.fs.normalize(a):lower() == vim.fs.normalize(b):lower()
  end
  if same(survivor_path, absorbed_path) then return nil, 'a note cannot merge into itself' end
  if vim.fn.filereadable(survivor_path) == 0 then return nil, 'survivor note not found: ' .. survivor_path end
  if vim.fn.filereadable(absorbed_path) == 0 then return nil, 'absorbed note not found: ' .. absorbed_path end
  if not M.agent_authored(survivor_path) then
    return nil, 'refusing to merge into a note no agent authored'
  end
  if not M.agent_authored(absorbed_path) then
    return nil, 'refusing to absorb a note no agent authored'
  end

  local citations = require('pkm.citations')
  local index     = require('pkm.index')
  local export    = require('pkm.export')

  local _, surv_id = citations.get_note_type_and_id(survivor_path)
  local _, abs_id  = citations.get_note_type_and_id(absorbed_path)

  -- Capture the absorbed note's neighbours as paths before anything mutates.
  local id_to_path = {}
  for id, d in pairs(citations.get_citable_items_map()) do id_to_path[id] = d.path end
  local edges = export.read_citation_edges(absorbed_path)
  local inbound = {}
  for _, id in ipairs(edges.cited_by) do if id_to_path[id] then inbound[#inbound + 1] = id_to_path[id] end end

  local abs_entry = index.get(absorbed_path)
  local abs_title = abs_entry and abs_entry.title
  local abs_body  = abs_entry and abs_entry.body or ''

  -- 1. Absorbed body → survivor (the survivor gains the absorbed note's cites).
  if #(abs_body:gsub('%s+', '')) > 0 then
    local block = {}
    if type(opts.heading) == 'string' and opts.heading ~= '' then
      block[#block + 1] = '## ' .. opts.heading
      block[#block + 1] = ''
    end
    for _, l in ipairs(to_lines(abs_body)) do block[#block + 1] = l end
    M.write_body(survivor_path, block, { mode = 'append' })
    -- The copy may carry a token pointing at the survivor (the absorbed note cited
    -- it): strip the resulting self-citation.
    if surv_id then pcall(function() citations.uncite(survivor_path, surv_id) end) end
  end

  -- 2. Redirect every note that cited the absorbed note onto the survivor.
  local redirected = 0
  for _, c in ipairs(inbound) do
    pcall(function() citations.uncite(c, abs_id) end)
    if not same(c, survivor_path) then
      pcall(function() citations.cite(c, survivor_path) end)
      redirected = redirected + 1
    end
  end

  -- 3. Clear the absorbed note's body so its targets drop it from their cited_by,
  --    leaving it graph-isolated before it is trashed.
  M.write_body(absorbed_path, '', { mode = 'replace' })

  -- 4. Union the absorbed note's topical tags into the survivor (best-effort).
  if abs_entry and type(abs_entry.tags) == 'table' then
    local add = {}
    for _, t in ipairs(abs_entry.tags) do if t ~= 'by-claude' then add[#add + 1] = t end end
    if #add > 0 then
      pcall(function() require('pkm.tags').write_note_tags(survivor_path, { add = add }) end)
    end
  end

  -- 5. Trash the absorbed note through the guard (it is assistant-authored).
  local ok, err = M.agent_delete(absorbed_path)
  if not ok then
    return nil, 'merged the body and graph, but could not trash the absorbed note: ' .. tostring(err)
  end

  index.invalidate(survivor_path)
  return survivor_path, nil, { redirected = redirected, absorbed_title = abs_title }
end

-- =============================================================================
-- SECTION: Agent authorship
-- =============================================================================
--
-- An agent writing in the vault marks its notes in their names —
-- NNNN_type_By<Author>_slug — and may delete only notes that carry such a mark.
-- The prefix is the last line of defence, not the first: once LLM-Claude exists,
-- the agent's own vault is where it writes by default and writing in another is
-- an explicit act (pkm.vault). The prefix still matters for exactly that case —
-- an agent acting inside a human's vault must not remove what a human wrote.

--- The agent that authored a note, read from its filename, or nil for a note no
--- agent marked. Read from the name, not frontmatter, because the name survives
--- copying and moving between vaults where a frontmatter field could be lost.
---@param path string
---@return string|nil author
function M.agent_authored(path)
  local stem      = vim.fn.fnamemodify(path, ':t:r')
  local name_part = stem:match('^%d+_%a+_(.+)$')
  if not name_part then return nil end
  return name_part:match('^By(%u%a*)_')
end

--- Delete a note **on an agent's behalf**, refusing any note no agent authored.
--- This is the deletion path the agent protocol calls; the human path
--- (`delete_note_safely`) is unguarded and interactive. The note is trashed,
--- never hard-deleted, so an over-eager agent is always recoverable.
---@param path string  Absolute note path
---@return boolean ok
---@return string|nil author_or_err  the author on success, the reason on refusal
function M.agent_delete(path)
  path = vim.fn.fnamemodify(path, ':p')
  if vim.fn.filereadable(path) == 0 then
    return false, 'note not found: ' .. path
  end

  local author = M.agent_authored(path)
  if not author then
    return false, 'refusing to delete a note no agent authored — '
      .. 'it has no By<agent> marker, so a human wrote it'
  end

  if not require('pkm.trash').trash_note(path) then
    return false, 'could not move the note to trash'
  end
  require('pkm.index').invalidate(path)
  pcall(function() require('pkm.views').refresh_sidebar_if_open() end)
  return true, author
end

--- Create a note that inherits the current note's tags.
---
--- A view is a filter over tags, so a note seeded with the same tags lands in
--- the same views as the note it came from — which is the point: continuing a
--- line of thought should not mean re-typing its classification.
--- The source note is read from the buffer, so unsaved tag edits count.
---@param note_type string|nil "note", "agg", or "bib" — prompts if nil
---@return string|nil filepath
function M.create_relative_note(note_type)
  local filepath = vim.fn.expand('%:p')
  if filepath == '' then
    vim.notify('[pkm] no note in this buffer to take tags from', vim.log.levels.WARN)
    return nil
  end

  local fm = require('pkm.yaml').parse_frontmatter(
    vim.api.nvim_buf_get_lines(0, 0, -1, false))
  if not fm then
    vim.notify('[pkm] no frontmatter found in this buffer', vim.log.levels.WARN)
    return nil
  end

  local source_tags = {}
  if type(fm.tags) == 'table' then
    source_tags = fm.tags
  elseif type(fm.tags) == 'string' then
    source_tags = { fm.tags }
  end

  if #source_tags == 0 then
    vim.notify(
      '[pkm] the current note has no tags — creating an untagged note',
      vim.log.levels.INFO)
  end

  return M.create_new_note(note_type, { tags = source_tags })
end

--- Create a timestamped scratchpad note. Prompts for an optional title.
---@return string filepath Absolute path of created scratchpad
function M.create_scratchpad()
  vim.fn.inputsave()
  local title = vim.fn.input("Scratchpad title (optional, Enter to skip): ")
  vim.fn.inputrestore()

  local ts = timestamp.now()
  local filename = timestamp.create_filename("scratch", ts, ".md")

  local scratchpad_path = utils.join(config.root_path, config.folders.scratchpad)
  utils.ensure_dir(scratchpad_path)

  local filepath = utils.join(scratchpad_path, filename)

  -- Only pass title to frontmatter if the user provided one
  local fm_data = title ~= "" and { title = title } or {}

  local frontmatter_lines = yaml.create_frontmatter("scratchpad", fm_data)
  table.insert(frontmatter_lines, "")

  vim.fn.writefile(frontmatter_lines, filepath)
  require('pkm.index').invalidate(filepath)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  vim.cmd("normal! G")
  vim.notify("Created scratchpad: " .. filename, vim.log.levels.INFO)
  return filepath
end

-- =============================================================================
-- SECTION: Note promotion and conversion
-- =============================================================================
--- Promote the current scratchpad note to a consolidated note or journal entry.
--- Only works when the current buffer is inside the scratchpad folder.
--- Uses Telescope if available, falls back to vim.ui.select.
function M.promote_note()
  local current_path = vim.fn.expand("%:p")

  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end

  if not current_path:find(config.folders.scratchpad, 1, true) then
    vim.notify("PKMNote promote: only works on scratchpad notes. Use :PKMNote convert for other types.", vim.log.levels.WARN)
    return
  end

  local targets = {
    { label = "Consolidated Note",  value = "note" },
    { label = "Journal Entry",      value = "journal" },
    { label = "Cancel",             value = "cancel" },
  }

  -- Check Telescope at call time, not at load time
  local has_telescope = package.loaded['telescope'] ~= nil
  if has_telescope then
    local ok, pickers      = pcall(require, "telescope.pickers")
    local _,  finders      = pcall(require, "telescope.finders")
    local _,  conf         = pcall(require, "telescope.config")
    local _,  actions      = pcall(require, "telescope.actions")
    local _,  action_state = pcall(require, "telescope.actions.state")

    if ok then
      pickers.new({}, {
        prompt_title = "Promote scratchpad to:",
        finder = finders.new_table {
          results = targets,
          entry_maker = function(entry)
            return { value = entry, display = entry.label, ordinal = entry.label }
          end,
        },
        sorter = conf.values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            if sel and sel.value.value ~= "cancel" then
              M.do_convert(current_path, "scratchpad", sel.value.value)
            end
          end)
          return true
        end,
      }):find()
      return
    end
  end

  -- Fallback
  vim.ui.select(targets, {
    prompt = "Promote scratchpad to:",
    format_item = function(item) return item.label end,
  }, function(sel)
    if sel and sel.value ~= "cancel" then
      M.do_convert(current_path, "scratchpad", sel.value)
    end
  end)
end

--- Move the current note to a different PKM folder and convert it to that
--- folder's format. Works from any folder, unlike promote_note which is
--- scratchpad-only. Presents all folders except the current one as targets,
--- then delegates to do_convert().
function M.transpose_note()
  local current_path = vim.fn.expand("%:p")

  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end

  local current_folder
  if current_path:find(config.folders.scratchpad, 1, true) then
    current_folder = "scratchpad"
  elseif current_path:find(config.folders.journal, 1, true) then
    current_folder = "journal"
  elseif current_path:find(config.folders.consolidated, 1, true) then
    current_folder = "consolidated"
  else
    vim.notify("PKMNote transpose: file is not inside a PKM folder", vim.log.levels.ERROR)
    return
  end

  -- Offer all folders except the current one
  local all_targets = {
    { label = "Consolidated Note", value = "note"      },
    { label = "Journal Entry",     value = "journal"   },
    { label = "Scratchpad",        value = "scratchpad" },
  }

  local targets = {}
  for _, t in ipairs(all_targets) do
    local skip = (current_folder == "consolidated" and t.value == "note")
              or (current_folder == "journal"      and t.value == "journal")
              or (current_folder == "scratchpad"   and t.value == "scratchpad")
    if not skip then
      table.insert(targets, t)
    end
  end

  vim.ui.select(targets, {
    prompt = "Transpose note to:",
    format_item = function(item) return item.label end,
  }, function(sel)
    if not sel then
      vim.notify("Transpose cancelled", vim.log.levels.INFO)
      return
    end
    M.do_convert(current_path, current_folder, sel.value)
  end)
end

--- Ask whether to delete the original file, then open the new file.
--- Shared finalisation step used by do_convert after file creation.
---@param original_path string Absolute path of the source file
---@param new_path string Absolute path of the newly created file
local function _finish_convert(original_path, new_path)
  require('pkm.index').invalidate(new_path)   -- file just written; index it now

  vim.fn.inputsave()
  local delete_original = vim.fn.input("Delete original? (y/N): ")
  vim.fn.inputrestore()

  if delete_original:lower() == "y" then
    vim.fn.delete(original_path)
    require('pkm.index').invalidate(original_path)  -- remove stale entry
    vim.notify("Original deleted: " .. vim.fn.fnamemodify(original_path, ":t"), vim.log.levels.INFO)
  end

  vim.cmd("edit " .. vim.fn.fnameescape(new_path))
  vim.notify("Promoted to: " .. vim.fn.fnamemodify(new_path, ":t"), vim.log.levels.INFO)
end

--- Perform the actual file conversion from one note type to another.
--- Reads current buffer content, builds new frontmatter, writes to new path.
--- For target "note", prompts for subtype and title asynchronously.
---@param current_path string Absolute path of note being converted
---@param current_type string Source type: "scratchpad", "journal", or "note"
---@param target string Destination type: "note", "journal", or "scratchpad"
function M.do_convert(current_path, current_type, target)
  -- Read current content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  
  -- Parse existing frontmatter
  local existing_fm, content_start = yaml.parse_frontmatter(lines)
  
  -- Get content without frontmatter
  local content = {}
  for i = content_start, #lines do
    table.insert(content, lines[i])
  end
  
  -- Create new file based on target type
  local new_path
  
  if target == "journal" then
    local ts = timestamp.now()
    
    local journal_filename = timestamp.create_filename("journal", ts, ".md")
    local journal_path = utils.join(config.root_path, config.folders.journal)
    utils.ensure_dir(journal_path)
    new_path = utils.join(journal_path, journal_filename)
    
    local fm_data = {}

    if existing_fm and existing_fm.tags then
      fm_data.tags = existing_fm.tags
    end
    
    local new_frontmatter = yaml.create_frontmatter("journal", fm_data)
    local new_content = vim.list_extend(new_frontmatter, content)
    
    vim.fn.writefile(new_content, new_path)

    local old_basename = vim.fn.fnamemodify(current_path, ":t:r")
    local new_basename = vim.fn.fnamemodify(new_path, ":t:r")

    require('pkm.citations').update_references_on_rename(old_basename,
    new_basename, nil)
    
  elseif target == "note" then
    -- Prompt for consolidated note subtype
    local note_types = {
      { label = "Regular Note",         value = "note" },
      { label = "Aggregate/Collection", value = "agg"  },
      { label = "Bibliography Entry",   value = "bib"  },
    }
  
    vim.ui.select(note_types, {
      prompt = "Consolidated note type:",
      format_item = function(item) return item.label end,
    }, function(type_sel)
      if not type_sel then
        vim.notify("Conversion cancelled", vim.log.levels.INFO)
        return
      end
  
      vim.fn.inputsave()
      local title = vim.fn.input("Note title (leave empty for unnamed): ")
      vim.fn.inputrestore()
  
      local note_number = get_next_note_number()
      local safe_title  = sanitize_title(title)
      local note_filename = string.format(
        "%04d_%s_%s.md", note_number, type_sel.value,
        safe_title ~= "" and safe_title or "unnamed"
      )
  
      local consolidated_path = utils.join(config.root_path, config.folders.consolidated)
      utils.ensure_dir(consolidated_path)
      new_path = utils.join(consolidated_path, note_filename)
  
      local fm_data = {
        title  = title ~= "" and title or "Unnamed Note",
      }
  
      if existing_fm then
        if existing_fm.tags   then fm_data.tags   = existing_fm.tags   end
        if existing_fm.author then fm_data.author = existing_fm.author end
      end
  
      local new_frontmatter = yaml.create_frontmatter("note", fm_data)
      local new_content     = vim.list_extend(new_frontmatter, content)
      vim.fn.writefile(new_content, new_path)

      local old_basename = vim.fn.fnamemodify(current_path, ":t:r")
      local new_basename = vim.fn.fnamemodify(new_path, ":t:r")
      require('pkm.citations').update_references_on_rename(old_basename, new_basename, fm_data.title)
  
      -- Continue to the "ask to delete original / open new file" block below
      _finish_convert(current_path, new_path)
    end)
    return  -- async from here; _finish_convert handles the rest
  elseif target == "scratchpad" then
    local ts = timestamp.now()
    local scratch_filename = timestamp.create_filename("scratch", ts, ".md")
    local scratch_path = utils.join(config.root_path, config.folders.scratchpad)
    utils.ensure_dir(scratch_path)
    new_path = utils.join(scratch_path, scratch_filename)
  
    local fm_data = {}
    if existing_fm and existing_fm.tags then
      fm_data.tags = existing_fm.tags
    end
  
    local new_frontmatter = yaml.create_frontmatter("scratchpad", fm_data)
    local new_content = vim.list_extend(new_frontmatter, content)
    vim.fn.writefile(new_content, new_path)
  
    local old_basename = vim.fn.fnamemodify(current_path, ":t:r")
    local new_basename = vim.fn.fnamemodify(new_path, ":t:r")
    require('pkm.citations').update_references_on_rename(old_basename, new_basename, nil)
  end


  
  -- Ask whether to delete original
  _finish_convert(current_path, new_path)
end

--- Convert note to the current folder's type: normalize current note to the
--- format required by its PKM folder. Adds missing frontmatter fields,
--- preserves existing ones. For consolidated notes without a valid PKM
--- filename, prompts for type/title and renames the file.
function M.convert_note()
  local current_path = vim.fn.expand("%:p")

  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end

  -- Detect which PKM folder the file lives in
  local folder_type
  if current_path:find(config.folders.scratchpad, 1, true) then
    folder_type = "scratchpad"
  elseif current_path:find(config.folders.journal, 1, true) then
    folder_type = "journal"
  elseif current_path:find(config.folders.consolidated, 1, true) then
    folder_type = "consolidated"
  else
    vim.notify("PKMNote convert: file is not inside a PKM folder", vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local existing_fm, content_start = yaml.parse_frontmatter(lines)
  existing_fm = existing_fm or {}

  -- Collect body lines (everything after frontmatter)
  local content = {}
  for i = content_start, #lines do
    table.insert(content, lines[i])
  end

  -- Write merged frontmatter back to disk and reload the buffer.
  -- create_frontmatter(key, existing_fm) keeps all existing values and
  -- fills in any missing fields from the template.
  local function apply_in_place(fm_key)
    local new_fm_lines = yaml.create_frontmatter(fm_key, existing_fm)
    local new_content = vim.list_extend(new_fm_lines, content)
    vim.fn.writefile(new_content, current_path)
    require('pkm.index').invalidate(current_path)
    vim.cmd("edit!")
    vim.notify("Converted to " .. folder_type .. " format", vim.log.levels.INFO)
  end

  if folder_type == "scratchpad" then
    apply_in_place("scratchpad")

  elseif folder_type == "journal" then
    apply_in_place("journal")

  elseif folder_type == "consolidated" then
    local basename    = vim.fn.fnamemodify(current_path, ":t:r")
    local number, note_type_part = basename:match("^(%d+)_([a-z]+)_")

    if number and note_type_part then
      -- File is already properly named: sync title from filename if absent
      if not existing_fm.title or existing_fm.title == "" then
        local name_part = basename:match("^%d+_[a-z]+_(.+)$")
        existing_fm.title = name_part and name_part:gsub("_", " ") or "Unnamed Note"
      end
    local fm_key = (note_type_part == "bib") and "bibliography"
            or (note_type_part == "agg") and "agg"
            or "note"
      apply_in_place(fm_key)

    else
      -- File does not follow PKM naming: prompt for type and title, then rename
      local note_types = {
        { label = "Regular Note",         value = "note" },
        { label = "Aggregate/Collection", value = "agg"  },
        { label = "Bibliography Entry",   value = "bib"  },
      }

      vim.ui.select(note_types, {
        prompt = "Note type:",
        format_item = function(item) return item.label end,
      }, function(type_sel)
        if not type_sel then
          vim.notify("Conversion cancelled", vim.log.levels.INFO)
          return
        end

        local default_title = (existing_fm.title and existing_fm.title ~= "")
          and existing_fm.title
          or basename:gsub("_", " ")

        vim.fn.inputsave()
        local title = vim.fn.input("Note title: ", default_title)
        vim.fn.inputrestore()
        if title == "" then title = "Unnamed Note" end
        existing_fm.title = title

        local note_number = get_next_note_number()
        local safe_title  = sanitize_title(title)
        local new_filename = string.format(
          "%04d_%s_%s.md", note_number, type_sel.value, safe_title
        )
        local dir      = vim.fn.fnamemodify(current_path, ":h")
        local new_path = utils.join(dir, new_filename)

        if vim.fn.filereadable(new_path) == 1 then
          vim.notify("Cannot convert: target already exists: " .. new_filename, vim.log.levels.ERROR)
          return
        end

        local fm_key = (type_sel.value == "bib") and "bibliography"
            or (type_sel.value == "agg") and "agg"
            or "note"
        local new_fm_lines = yaml.create_frontmatter(fm_key, existing_fm)
        local new_content  = vim.list_extend(new_fm_lines, content)

        vim.fn.writefile(new_content, new_path)
        local old_basename = vim.fn.fnamemodify(current_path, ":t:r")
        local new_basename = vim.fn.fnamemodify(new_path, ":t:r")
        require('pkm.citations').update_references_on_rename(old_basename, new_basename, title)
        require('pkm.index').invalidate(new_path)

        vim.fn.inputsave()
        local del = vim.fn.input("Delete original file? (y/N): ")
        vim.fn.inputrestore()
        if del:lower() == "y" then
          vim.fn.delete(current_path)
          require('pkm.index').invalidate(current_path)
        end

        vim.cmd("edit " .. vim.fn.fnameescape(new_path))
        vim.notify("Converted to: " .. new_filename, vim.log.levels.INFO)
      end)
    end
  end
end

--- Change the type of an already-named consolidated note (note/agg/bib).
--- Renames the file to reflect the new type and propagates the change
--- through all citations via update_references_on_rename.
--- Only works on consolidated notes with a valid PKM filename.
function M.change_note_type()
  local current_path = vim.fn.expand("%:p")

  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end

  if not current_path:find(config.folders.consolidated, 1, true) then
    vim.notify("PKMNote changetype: only works on consolidated notes.", vim.log.levels.ERROR)
    return
  end

  local basename = vim.fn.fnamemodify(current_path, ":t:r")
  local number, current_type = basename:match("^(%d+)_([a-z]+)_")

  if not number or not current_type then
    vim.notify("PKMNote changetype: file does not have a valid PKM filename. Use :PKMNote convert first.", vim.log.levels.WARN)
    return
  end

  local note_types = {
    { label = "Regular Note",         value = "note" },
    { label = "Aggregate/Collection", value = "agg"  },
    { label = "Bibliography Entry",   value = "bib"  },
  }

  -- Filter out current type
  local targets = {}
  for _, t in ipairs(note_types) do
    if t.value ~= current_type then
      table.insert(targets, t)
    end
  end

  vim.ui.select(targets, {
    prompt = string.format("Change type from '%s' to:", current_type),
    format_item = function(item) return item.label end,
  }, function(sel)
    if not sel then
      vim.notify("Type change cancelled.", vim.log.levels.INFO)
      return
    end

    local dir          = vim.fn.fnamemodify(current_path, ":h")
    local name_part    = basename:match("^%d+_[a-z]+_(.+)$")
    local new_filename = string.format("%04d_%s_%s.md", tonumber(number), sel.value, name_part)
    local new_path     = utils.join(dir, new_filename)

    if vim.fn.filereadable(new_path) == 1 then
      vim.notify("Cannot change type: target already exists: " .. new_filename, vim.log.levels.ERROR)
      return
    end

    -- Update frontmatter template
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local existing_fm, content_start = yaml.parse_frontmatter(lines)
    existing_fm = existing_fm or {}

    local content = {}
    for i = content_start, #lines do
      table.insert(content, lines[i])
    end

    local fm_key = (sel.value == "bib") and "bibliography"
               or (sel.value == "agg") and "agg"
               or "note"
    local new_fm_lines = yaml.create_frontmatter(fm_key, existing_fm)
    local new_content  = vim.list_extend(new_fm_lines, content)

    -- Write the regenerated frontmatter directly to the new path — the
    -- content is being fully replaced anyway, so a separate rename step
    -- before the write is redundant.
    if vim.fn.writefile(new_content, new_path) ~= 0 then
      vim.notify("PKMNote changetype: failed to write new file.", vim.log.levels.ERROR)
      return
    end
    if utils.normalize(current_path) ~= utils.normalize(new_path) then
      vim.fn.delete(current_path)
    end

    -- Propagate rename through citations
    local old_basename = vim.fn.fnamemodify(current_path, ":t:r")
    local new_basename = vim.fn.fnamemodify(new_path, ":t:r")
    require('pkm.citations').update_references_on_rename(old_basename,
    new_basename, existing_fm.title)

    local index = require('pkm.index')
    index.invalidate(current_path)  -- renamed away; remove stale entry
    index.invalidate(new_path)      -- written with new frontmatter; index it

    -- Redirect buffer via pure API — never :saveas/:write — so an otherwise-
    -- unmodified type change cannot trigger an E13 forced-write prompt.
    -- Only run after the write above has succeeded (see rename_note).
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(bufnr, new_path)
    vim.bo[bufnr].modified = false
    vim.notify(string.format("Changed type: %s → %s", current_type, sel.value), vim.log.levels.INFO)
  end)
end

-- =============================================================================
-- SECTION: Note renaming
-- =============================================================================

--- Determine whether two paths refer to the same on-disk file object.
--- Primary check: device + inode equality via vim.loop.fs_stat — reliable
--- for case-only renames on any filesystem, since the OS resolves both
--- paths to the same object before the rename is applied.
--- Fallback: case-insensitive path equality, applied ONLY on Windows/WSL
--- (case-insensitive filesystems). Never applied on a case-sensitive
--- filesystem, where two case-differing paths are genuinely distinct files.
---@param path_a string
---@param path_b string
---@return boolean
local function is_same_file(path_a, path_b)
  local uv = vim.uv or vim.loop
  local stat_a = uv.fs_stat(path_a)
  local stat_b = uv.fs_stat(path_b)
  if stat_a and stat_b and stat_a.dev == stat_b.dev and stat_a.ino == stat_b.ino then
    return true
  end
  if utils.is_windows or utils.is_wsl then
    return utils.normalize(path_a):lower() == utils.normalize(path_b):lower()
  end
  return false
end

-- Exposed for test/test_v154_p1.lua only; not part of the module's public API.
M._is_same_file = is_same_file

--- Rename one note file on disk, without asking anything and without
--- propagating. The mechanical half of `rename_note`, extracted so a batch can
--- reuse it: the two-step dance a case-only rename needs on a case-insensitive
--- filesystem, the awareness of a buffer holding the file, and the index
--- invalidation of both paths are subtle enough that a second implementation
--- would be a second set of bugs.
---
--- **Propagation is the caller's job.** A batch rewrites citing notes once for
--- the whole set, not once per file — see `citations.update_references_on_renames`.
---@param path     string  Absolute path of the note as it is now
---@param new_stem string  New filename stem, without extension
---@return boolean ok
---@return string|nil new_path  Absolute path after the rename
---@return string|nil err
function M.rename_file(path, new_stem)
  local dir      = vim.fn.fnamemodify(path, ':h')
  local new_path = utils.join(dir, new_stem .. '.md')

  if new_path:gsub('\\', '/') == path:gsub('\\', '/') then
    return true, path
  end

  local target_exists = vim.fn.filereadable(new_path) == 1
  local same_file     = target_exists and is_same_file(path, new_path)

  if target_exists and not same_file then
    return false, nil, 'target already exists: ' .. new_stem .. '.md'
  end

  -- Content comes from the buffer when one holds this file, so a rename never
  -- discards edits the user has not saved; from disk otherwise.
  local bufnr = require('pkm.bufsync').buffer_for(path)
  local lines = bufnr and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                or vim.fn.readfile(path)

  if same_file then
    -- Case-only rename on a case-insensitive filesystem: path and new_path
    -- resolve to the SAME directory entry, so writing directly to new_path
    -- would just reopen the existing file under its current on-disk casing —
    -- the stored name would never actually change. Force it via a two-step
    -- rename through a distinct temp name; a single rename() call is not
    -- reliable for case-only changes on every case-insensitive filesystem.
    local tmp_path = path .. '.pkmtmp'
    if vim.fn.filereadable(tmp_path) == 1 then
      return false, nil, 'stale temp file present, try again'
    end
    if vim.fn.rename(path, tmp_path) ~= 0 then
      return false, nil, 'could not stage temp file'
    end
    if vim.fn.rename(tmp_path, new_path) ~= 0 then
      vim.fn.rename(tmp_path, path)  -- best-effort: don't strand it under .pkmtmp
      return false, nil, 'could not apply new casing'
    end
    vim.fn.writefile(lines, new_path)
  else
    -- Genuine new target: write-then-delete avoids :saveas/:write entirely, so
    -- an otherwise-unmodified rename cannot trigger an E13 forced-write prompt.
    if vim.fn.writefile(lines, new_path) ~= 0 then
      return false, nil, 'could not write ' .. new_stem .. '.md'
    end
    vim.fn.delete(path)
  end

  if bufnr then
    vim.api.nvim_buf_set_name(bufnr, new_path)
    -- nvim_buf_set_name leaves the buffer NAMING a file it has not "edited"
    -- (Vim's BF_NOTEDITED): a later :w to that now-existing path raises E13
    -- ("File exists, add ! to override"), even though the buffer content already
    -- matches disk. Force one silent, autocmd-free write of the identical
    -- on-disk bytes to clear that flag and stamp the buffer's on-disk timestamp,
    -- so ordinary saves — and the post-rename title write-through in
    -- edit_frontmatter — are clean instead of prompting for `!`.
    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.cmd, 'silent keepalt noautocmd write!')
    end)
    vim.bo[bufnr].modified = false
  end

  local index = require('pkm.index')
  index.invalidate(path)
  index.invalidate(new_path)

  return true, new_path
end

--- Rename the current PKM note file.
--- For consolidated notes: preserves number and type prefix, renames the title part.
--- For journal/scratchpad: allows renaming the full stem.
--- Does not modify the title frontmatter field.
--- Propagates the rename through citations via update_references_on_rename.
---
--- Interactive and programmatic are the one command. With `new_name` given
--- (`:PKMNote rename nome novo`) it renames straight; without one it prompts,
--- seeded with the current name. In both cases `new_name` is the *human* name —
--- the number and type prefix of a consolidated note are kept for you — and it
--- is sanitised the same way the prompt's input is.
---@param new_name string|nil  When nil, prompt; otherwise the new name part
---@return nil
function M.rename_note(new_name)
  local filepath = vim.fn.expand('%:p')
  local old_stem = vim.fn.fnamemodify(filepath, ':t:r')

  local folder_type
  if filepath:find(config.folders.consolidated, 1, true) then
    folder_type = 'consolidated'
  elseif filepath:find(config.folders.journal, 1, true) then
    folder_type = 'journal'
  elseif filepath:find(config.folders.scratchpad, 1, true) then
    folder_type = 'scratchpad'
  else
    vim.notify('[pkm] file is not inside a PKM folder', vim.log.levels.WARN)
    return
  end

  local new_stem

  if folder_type == 'consolidated' then
    local number, note_type, name_part = old_stem:match('^(%d+)_([a-z]+)_(.+)$')
    if not number then
      vim.notify('[pkm] unrecognized consolidated note filename', vim.log.levels.WARN)
      return
    end
    -- An agent-authorship marker (By<Author>_) is identity, not description:
    -- like the number/type prefix it is kept for you and never enters the
    -- editable name, so a rename cannot silently drop it (which would make
    -- agent_authored read the note as human-written and flip the delete guard).
    -- Same pattern as M.agent_authored.
    local marker, bare = name_part:match('^(By%u%a*)_(.+)$')
    local editable = bare or name_part
    local input = new_name
    if input == nil then
      vim.fn.inputsave()
      input = vim.fn.input('Rename note: ', (editable:gsub('_', ' ')))
      vim.fn.inputrestore()
    end
    if not input or input == '' then return end
    local safe_name = sanitize_title(input)
    if marker then safe_name = marker .. '_' .. safe_name end
    new_stem = string.format('%04d_%s_%s', tonumber(number), note_type, safe_name)
  else
    local input = new_name
    if input == nil then
      vim.fn.inputsave()
      input = vim.fn.input('Rename to (stem, no extension): ', old_stem)
      vim.fn.inputrestore()
    end
    if not input or input:match('^%s*$') then return end
    new_stem = sanitize_title(input)
  end

  local ok, new_filepath, err = M.rename_file(filepath, new_stem)
  if not ok then
    vim.notify('[pkm] rename failed: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
    return
  end
  if new_filepath == filepath then return end   -- nothing to do

  local fm, _ = yaml.parse_frontmatter(vim.fn.readfile(new_filepath))
  local display_title = (fm and type(fm.title) == 'string' and fm.title ~= '')
                        and fm.title
                        or new_stem:gsub('_', ' ')

  require('pkm.citations').update_references_on_rename(old_stem, new_stem, display_title)
  vim.notify('[pkm] renamed to: ' .. new_stem .. '.md', vim.log.levels.INFO)

  -- Non-obstructive follow-up, INTERACTIVE PATH ONLY. When the name was typed at
  -- the prompt (bare `:PKMNote rename`, so new_name is nil), offer to change the
  -- title too. When a name was passed as an argument (`:PKMNote rename foo`, or
  -- any script / headless caller), the command stays deterministic and never
  -- prompts — that is the command-surface contract ("arguments = script-callable"),
  -- and a prompt there would block a headless run. The filename rename above has
  -- already succeeded and is never undone here: <C-c>/<Esc> (cancelreturn hands
  -- back the current title), an unchanged value, or an emptied value all KEEP the
  -- current title; only a genuinely new one is written, through the buffer holding
  -- the just-renamed file, so there is no later W12 :w prompt.
  if new_name == nil then
    local current_title = (fm and type(fm.title) == 'string') and fm.title or ''
    vim.fn.inputsave()
    local new_title = vim.fn.input({
      prompt       = 'Now renaming the title (empty or unchanged keeps it): ',
      default      = current_title,
      cancelreturn = current_title,
    })
    vim.fn.inputrestore()

    if new_title and new_title ~= '' and new_title ~= current_title then
      local ok_t, err_t = M.set_title_at(new_filepath, new_title)
      vim.notify(ok_t and ('[pkm] title set to: ' .. new_title)
                       or  ('[pkm] title unchanged: ' .. (err_t or 'error')),
                 ok_t and vim.log.levels.INFO or vim.log.levels.WARN)
    end
  end
end

-- =============================================================================
-- SECTION: Headless lifecycle seams (agent / pkm.api)
-- =============================================================================
-- The pure cores behind promote/transpose, changetype, and rename. Each takes
-- an explicit path (never the current buffer), reads content from a buffer
-- holding the file when one exists — so unsaved edits survive — and from disk
-- otherwise, prompts for nothing, opens no buffer, and returns
-- `new_path, err, meta`. They are the headless twins of the interactive
-- functions above, in the mould of write_new_note ↔ create_new_note; the
-- interactive paths keep their pickers and prompts, these keep the write logic
-- callable from `nvim --headless` and from pkm.api.

--- Move a note to another PKM type, writing a new file in the target folder,
--- propagating citations, and (only when asked) deleting the original. The pure
--- core behind :PKMNote promote and :PKMNote transpose.
---@param path   string  Absolute path of the source note
---@param target string  'note' | 'journal' | 'scratchpad'
---@param opts   table|nil  { subtype?='note'|'agg'|'bib', title?=string, delete_original?=boolean }
---@return string|nil new_path
---@return string|nil err
---@return table|nil  meta  { filename, type, title, original_deleted }
function M.convert_file(path, target, opts)
  opts = opts or {}
  if vim.fn.filereadable(path) ~= 1 then
    return nil, 'no such file: ' .. path
  end

  local bufnr = require('pkm.bufsync').buffer_for(path)
  local lines = bufnr and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
              or vim.fn.readfile(path)
  local existing_fm, content_start = yaml.parse_frontmatter(lines)
  local content = {}
  for i = content_start, #lines do content[#content + 1] = lines[i] end

  local new_path, new_frontmatter, title

  if target == 'journal' then
    local ts = timestamp.now()
    local journal_path = utils.join(config.root_path, config.folders.journal)
    utils.ensure_dir(journal_path)
    new_path = utils.join(journal_path, timestamp.create_filename('journal', ts, '.md'))
    local fm_data = {}
    if existing_fm and existing_fm.tags then fm_data.tags = existing_fm.tags end
    new_frontmatter = yaml.create_frontmatter('journal', fm_data)

  elseif target == 'scratchpad' then
    local ts = timestamp.now()
    local scratch_path = utils.join(config.root_path, config.folders.scratchpad)
    utils.ensure_dir(scratch_path)
    new_path = utils.join(scratch_path, timestamp.create_filename('scratch', ts, '.md'))
    local fm_data = {}
    if existing_fm and existing_fm.tags then fm_data.tags = existing_fm.tags end
    new_frontmatter = yaml.create_frontmatter('scratchpad', fm_data)

  elseif target == 'note' then
    local subtype = opts.subtype or 'note'
    if subtype ~= 'note' and subtype ~= 'agg' and subtype ~= 'bib' then
      return nil, "invalid subtype '" .. tostring(subtype) .. "' (note|agg|bib)"
    end
    title = opts.title
    if not title or title == '' then
      title = (existing_fm and type(existing_fm.title) == 'string' and existing_fm.title ~= '')
              and existing_fm.title or 'Unnamed Note'
    end
    local note_number = get_next_note_number()
    local safe_title  = sanitize_title(title)
    local note_filename = string.format('%04d_%s_%s.md',
      note_number, subtype, safe_title ~= '' and safe_title or 'unnamed')
    local consolidated_path = utils.join(config.root_path, config.folders.consolidated)
    utils.ensure_dir(consolidated_path)
    new_path = utils.join(consolidated_path, note_filename)
    local fm_data = { title = title }
    if existing_fm then
      if existing_fm.tags   then fm_data.tags   = existing_fm.tags   end
      if existing_fm.author then fm_data.author = existing_fm.author end
    end
    local fm_key = (subtype == 'bib') and 'bibliography'
               or (subtype == 'agg') and 'agg'
               or 'note'
    new_frontmatter = yaml.create_frontmatter(fm_key, fm_data)

  else
    return nil, "unknown target type '" .. tostring(target) .. "' (note|journal|scratchpad)"
  end

  local new_content = vim.list_extend(new_frontmatter, content)
  if vim.fn.writefile(new_content, new_path) ~= 0 then
    return nil, 'could not write ' .. vim.fn.fnamemodify(new_path, ':t')
  end

  local old_basename = vim.fn.fnamemodify(path, ':t:r')
  local new_basename = vim.fn.fnamemodify(new_path, ':t:r')
  require('pkm.citations').update_references_on_rename(old_basename, new_basename, title)

  local index = require('pkm.index')
  index.invalidate(new_path)

  local original_deleted = false
  if opts.delete_original and utils.normalize(path) ~= utils.normalize(new_path) then
    vim.fn.delete(path)
    index.invalidate(path)
    original_deleted = true
  end

  return new_path, nil, {
    filename = new_basename .. '.md',
    type = target,
    title = title,
    original_deleted = original_deleted,
  }
end

--- Change the type of an already-named consolidated note (note/agg/bib),
--- renaming the file and propagating the change through every citation. The
--- pure core behind :PKMNote changetype.
---@param path     string  Absolute path of the consolidated note
---@param new_type string  'note' | 'agg' | 'bib'
---@return string|nil new_path
---@return string|nil err
---@return table|nil  meta  { filename, type, title }
function M.changetype_file(path, new_type)
  if new_type ~= 'note' and new_type ~= 'agg' and new_type ~= 'bib' then
    return nil, "invalid type '" .. tostring(new_type) .. "' (note|agg|bib)"
  end
  if vim.fn.filereadable(path) ~= 1 then
    return nil, 'no such file: ' .. path
  end

  local basename = vim.fn.fnamemodify(path, ':t:r')
  local number, current_type, name_part = basename:match('^(%d+)_([a-z]+)_(.+)$')
  if not number then
    return nil, 'not a valid consolidated filename: ' .. basename
  end
  if current_type == new_type then
    return path, nil, { filename = basename .. '.md', type = new_type }
  end

  local dir          = vim.fn.fnamemodify(path, ':h')
  local new_filename = string.format('%04d_%s_%s.md', tonumber(number), new_type, name_part)
  local new_path     = utils.join(dir, new_filename)
  if vim.fn.filereadable(new_path) == 1 then
    return nil, 'target already exists: ' .. new_filename
  end

  local bufnr = require('pkm.bufsync').buffer_for(path)
  local lines = bufnr and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
              or vim.fn.readfile(path)
  local existing_fm, content_start = yaml.parse_frontmatter(lines)
  existing_fm = existing_fm or {}
  local content = {}
  for i = content_start, #lines do content[#content + 1] = lines[i] end

  local fm_key = (new_type == 'bib') and 'bibliography'
             or (new_type == 'agg') and 'agg'
             or 'note'
  local new_content = vim.list_extend(yaml.create_frontmatter(fm_key, existing_fm), content)
  if vim.fn.writefile(new_content, new_path) ~= 0 then
    return nil, 'could not write ' .. new_filename
  end
  if utils.normalize(path) ~= utils.normalize(new_path) then
    vim.fn.delete(path)
  end

  local new_basename = vim.fn.fnamemodify(new_path, ':t:r')
  require('pkm.citations').update_references_on_rename(basename, new_basename, existing_fm.title)

  local index = require('pkm.index')
  index.invalidate(path)
  index.invalidate(new_path)

  if bufnr then
    vim.api.nvim_buf_set_name(bufnr, new_path)
    vim.bo[bufnr].modified = false
  end

  return new_path, nil, {
    filename = new_basename .. '.md',
    type = new_type,
    title = existing_fm.title,
  }
end

--- Rename a note file at an explicit path — keeping a consolidated note's number
--- and type prefix, sanitising the human name the same way the prompt does — and
--- propagate the rename through every citation. The pure core behind
--- :PKMNote rename. Reuses rename_file for the on-disk half.
---@param path     string  Absolute path of the note
---@param new_name string  New human name (prefix kept for consolidated notes)
---@return string|nil new_path
---@return string|nil err
---@return table|nil  meta  { filename, title }
function M.rename_note_at(path, new_name)
  if vim.fn.filereadable(path) ~= 1 then
    return nil, 'no such file: ' .. path
  end
  local old_stem = vim.fn.fnamemodify(path, ':t:r')

  local folder_type
  if path:find(config.folders.consolidated, 1, true) then
    folder_type = 'consolidated'
  elseif path:find(config.folders.journal, 1, true) then
    folder_type = 'journal'
  elseif path:find(config.folders.scratchpad, 1, true) then
    folder_type = 'scratchpad'
  else
    return nil, 'file is not inside a PKM folder'
  end

  local new_stem
  if folder_type == 'consolidated' then
    local number, note_type, name_part = old_stem:match('^(%d+)_([a-z]+)_(.+)$')
    if not number then
      return nil, 'unrecognized consolidated note filename: ' .. old_stem
    end
    if not new_name or new_name == '' then return nil, 'new name is empty' end
    -- Preserve the By<Author>_ authorship marker across the rename — it is
    -- identity carried in the name (see M.agent_authored), so new_name is the
    -- bare human name and the marker is re-attached for the caller.
    local marker = name_part:match('^(By%u%a*)_')
    local safe = sanitize_title(new_name)
    if marker then safe = marker .. '_' .. safe end
    new_stem = string.format('%04d_%s_%s', tonumber(number), note_type, safe)
  else
    if not new_name or new_name:match('^%s*$') then return nil, 'new name is empty' end
    new_stem = sanitize_title(new_name)
  end

  local ok, new_filepath, err = M.rename_file(path, new_stem)
  if not ok then return nil, err or 'rename failed' end
  if new_filepath == path then
    return path, nil, { filename = old_stem .. '.md' }
  end

  local fm = yaml.parse_frontmatter(vim.fn.readfile(new_filepath))
  local display_title = (fm and type(fm.title) == 'string' and fm.title ~= '')
                        and fm.title or new_stem:gsub('_', ' ')
  require('pkm.citations').update_references_on_rename(old_stem, new_stem, display_title)

  return new_filepath, nil, { filename = new_stem .. '.md', title = display_title }
end

--- Apply a mutation to a note's frontmatter and persist it, keeping any open
--- buffer honest — the write-through pattern from citations.manage_backlink.
--- An **unmodified** buffer is written THROUGH (re-stamping Neovim's stored
--- on-disk timestamp, so a later user `:w` sees no phantom W12 external-change
--- prompt); a **modified** buffer receives the change in-buffer and the user's
--- next `:w` persists it (so unsaved edits are never discarded and the index is
--- not invalidated early); a note open in **no** buffer is written to disk.
---@param path   string  Absolute note path
---@param mutate fun(fm: table): boolean  Return true when it changed something
---@return boolean ok
---@return string|nil err
local function edit_frontmatter(path, mutate)
  path = vim.fn.fnamemodify(path, ':p')
  if vim.fn.filereadable(path) ~= 1 then
    return false, 'no such file: ' .. path
  end

  local bufnr        = require('pkm.bufsync').buffer_for(path)
  local buf_modified = bufnr and vim.bo[bufnr].modified or false

  -- A modified buffer may differ from disk; read from it so we compose with the
  -- user's edits rather than overwrite them. Otherwise disk is the truth.
  local content = (bufnr and buf_modified)
    and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    or  vim.fn.readfile(path)

  local fm, content_start = yaml.parse_frontmatter(content)
  if not fm then return false, 'no frontmatter found' end

  if not mutate(fm) then return true end   -- nothing to change: a no-op success

  local index = require('pkm.index')
  if bufnr then
    local fm_lines    = yaml.generate_yaml(fm)
    local new_content = { '---' }
    for _, line in ipairs(fm_lines)    do new_content[#new_content + 1] = line end
    new_content[#new_content + 1] = '---'
    for i = content_start, #content    do new_content[#new_content + 1] = content[i] end

    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, new_content)
      if not buf_modified then
        -- Persist by writing THROUGH the buffer (see manage_backlink): a disk
        -- writefile would leave this buffer's load-time timestamp stale and a
        -- later :w would see a phantom external change (W12). 'noautocmd' keeps
        -- BufWritePost from re-firing on a change flow that already handles it.
        pcall(vim.cmd, 'silent keepjumps noautocmd write')
      end
    end)

    if not buf_modified then index.invalidate(path) end
    pcall(function() require('pkm.syntax').refresh_fold(bufnr) end)
  else
    yaml.save_frontmatter(fm, content_start, path)
    index.invalidate(path)
  end

  return true
end

--- Set a note's frontmatter title on disk, by path — the persisting twin of the
--- buffer-only `set_title`. Keeps an open buffer in step (write-through) and
--- propagates the new title to every note that cites this one. Headless-safe
--- (pkm.api.set_title), so an agent can correct a title without an uncite →
--- delete → recreate cycle.
---@param path      string  Absolute note path
---@param new_title string  Taken verbatim (may be empty)
---@return boolean ok
---@return string|nil err
function M.set_title_at(path, new_title)
  local changed = false
  local ok, err = edit_frontmatter(path, function(fm)
    if fm.title == new_title then return false end
    fm.title = new_title
    changed  = true
    return true
  end)
  if not ok then return false, err end

  if changed then
    local citations = require('pkm.citations')
    local _, id = citations.get_note_type_and_id(path)
    -- Propagate the KNOWN new value, not a re-read (which could be stale).
    if id then citations.propagate_titles({ [id] = new_title }) end
  end
  return true
end

--- Set a note's source metadata (source_author / source_type) on disk, by path.
--- The post-hoc setter for a bib note's provenance: create-time values were the
--- only way to set these, so a correction meant recreating the note. Only the
--- keys present in `opts` are written; source metadata is not part of the
--- citation graph, so nothing is propagated.
---@param path string  Absolute note path
---@param opts table   { author?=string, type?=string }
---@return boolean ok
---@return string|nil err
function M.set_source_meta_at(path, opts)
  opts = opts or {}
  return edit_frontmatter(path, function(fm)
    local changed = false
    if opts.author ~= nil and fm.source_author ~= opts.author then
      fm.source_author = opts.author
      changed = true
    end
    if opts.type ~= nil and fm.source_type ~= opts.type then
      fm.source_type = opts.type
      changed = true
    end
    return changed
  end)
end

-- =============================================================================
-- SECTION: Navigation
-- =============================================================================
--- Insert a [[wiki-link]] to another note at the current cursor position.
--- Searches only the consolidated folder. Uses vim.ui.select for picking.
function M.link_to_note()
  local source_path = vim.fn.expand("%:p")
  if source_path == "" then
    vim.notify("Cannot link from unnamed buffer", vim.log.levels.WARN)
    return
  end
  
  -- Get all notes
  local consolidated_path = utils.join(config.root_path, config.folders.consolidated)
  local files = vim.fn.glob(consolidated_path .. utils.sep .. "*.md", false, true)
  
  local notes = {}
  for _, file in ipairs(files) do
    if file ~= source_path then
      local basename = vim.fn.fnamemodify(file, ":t:r")
      local number, note_type, name = basename:match("^(%d+)_([a-z]+)_(.+)$")
      
      if number and note_type and name then
        local display_name = string.format("[%s%s] %s", note_type, number,
        require('pkm.citations').get_note_title(file))
        
        table.insert(notes, {
          path = file,
          display = display_name,
          basename = basename,
        })
      end
    end
  end
  
  if #notes == 0 then
    vim.notify("No notes available to link", vim.log.levels.INFO)
    return
  end
  
  vim.ui.select(notes, {
    prompt = "Link to which note?",
    format_item = function(item) return item.display end,
  }, function(selected)
    if not selected then return end
    
    local link = "[[" .. selected.basename .. "]]"
    
    local _, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local new_line = line:sub(1, col) .. link .. line:sub(col + 1)
    vim.api.nvim_set_current_line(new_line)
    
    vim.notify("Linked to: " .. selected.basename, vim.log.levels.INFO)
  end)
end

--- Open the note linked under the cursor via [[wiki-link]] syntax.
--- Searches consolidated, journal, and scratchpad folders in that order.
function M.follow_link()
  local line = vim.api.nvim_get_current_line()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0)) -- col is 0-indexed
  
  -- Find all wiki-links in the line and check which one contains the cursor
  local link_target = nil
  local search_start = 1
  
  while true do
    -- Find next [[...]] link
    local link_start, link_end, content = line:find("%[%[([^%]]+)%]%]", search_start)
    
    if not link_start then
      break -- No more links found
    end
    
    -- Check if cursor is within this link (convert to 0-indexed comparison)
    -- link_start and link_end are 1-indexed from Lua string positions
    if col >= link_start - 1 and col < link_end then
      link_target = content
      break
    end
    
    -- Move search position forward
    search_start = link_end + 1
  end
  
  if not link_target then
    -- No wiki-link under cursor -- try a citation token (note[0042] etc.)
    -- next, so gf follows either link type instead of only [[wiki-links]].
    -- Delegates to goto_citation()'s own lookup so the two never diverge.
    if require('pkm.citations').goto_citation(true) then return end
    vim.notify("No link under cursor", vim.log.levels.WARN)
    return
  end
  
  -- Search all known folders for a file with this basename
  local potential_paths = {
    utils.join(config.root_path, config.folders.consolidated, link_target .. ".md"),
    utils.join(config.root_path, config.folders.journal, link_target .. ".md"),
    utils.join(config.root_path, config.folders.scratchpad, link_target .. ".md"),
  }
  
  for _, target_path in ipairs(potential_paths) do
    if vim.fn.filereadable(target_path) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      vim.notify("Opened: " .. vim.fn.fnamemodify(target_path, ":t"), vim.log.levels.INFO)
      return
    end
  end
  
  vim.notify("File not found: " .. link_target .. ".md", vim.log.levels.ERROR)
end

--- Show all notes that contain a [[wiki-link]] to the current note.
--- Searches all three PKM folders. Opens selected backlink with vim.ui.select.
function M.show_backlinks()
  local current_path = vim.fn.expand("%:p")
  if current_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end
  
  local current_basename = vim.fn.fnamemodify(current_path, ":t:r")
  
  local search_paths = {
    utils.join(config.root_path, config.folders.consolidated),
    utils.join(config.root_path, config.folders.journal),
    utils.join(config.root_path, config.folders.scratchpad),
  }
  
  local backlinks = {}
  
  for _, search_path in ipairs(search_paths) do
    local files = vim.fn.glob(search_path .. utils.sep .. "*.md", false, true)
    
    for _, file in ipairs(files) do
      if file ~= current_path then
        local content = vim.fn.readfile(file)
        local has_link = false
        
        for _, line in ipairs(content) do
          if line:match("%[%[" .. vim.pesc(current_basename) .. "%]%]") then
            has_link = true
            break
          end
        end
        
        if has_link then
          table.insert(backlinks, {
            path = file,
            display = require('pkm.citations').get_note_title(file),
          })
        end
      end
    end
  end
  
  if #backlinks == 0 then
    vim.notify("No backlinks found", vim.log.levels.INFO)
    return
  end
  
  vim.ui.select(backlinks, {
    prompt = "Backlinks to current note:",
    format_item = function(item) return item.display end,
  }, function(selected)
    if selected then
      vim.cmd("edit " .. vim.fn.fnameescape(selected.path))
    end
  end)
end

-- =============================================================================
-- SECTION: Import
-- =============================================================================
--- Import an external file into the PKM consolidated folder.
--- Preserves existing frontmatter fields, prompts for type and title,
--- generates a new numbered filename, and optionally deletes the original.
function M.import_note()
  local current_path = vim.fn.expand("%:p")
  local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  
  -- Check if already in system
  if current_path ~= "" and current_path:find(config.root_path, 1, true) then
    vim.notify("This file is already in your PKM system.", vim.log.levels.WARN)
    return
  end

  -- Parse any existing frontmatter
  local existing_fm, content_start = yaml.parse_frontmatter(current_lines)
  local title_guess = "Imported Note"
  
  if existing_fm and existing_fm.title then
    title_guess = existing_fm.title
  elseif current_path ~= "" then
    title_guess = vim.fn.fnamemodify(current_path, ":t:r")
  elseif content_start and current_lines[content_start] then
    -- Try to guess title from first line if it looks like a header
    local first_line = current_lines[content_start]
    if first_line:match("^#+ ") then
        title_guess = first_line:gsub("^#+ ", "")
    end
  end

  -- Prompt for Type
  vim.ui.select({"note", "bib", "agg"}, { prompt = "Select Import Type:" }, function(selected_type)
    if not selected_type then return end
    
    -- Prompt for Title
    vim.ui.input({ prompt = "Title: ", default = title_guess }, function(input_title) 
      if input_title == nil then return end -- Cancelled
      local title = input_title
      if title == "" then title = "Unnamed" end

      -- Prepare Metadata
      local fm_data = existing_fm or {}
      fm_data.title = title
      if not fm_data.created_on then fm_data.created_on = timestamp.to_iso8601() end
      
      -- If bib, ensure source fields exist (prompt optional, or just blank)
      if selected_type == "bib" then
         if not fm_data.source_author then fm_data.source_author = "" end
         if not fm_data.source_type then fm_data.source_type = "book" end
      end

      -- Generate Target Path
      local note_number = get_next_note_number()
      local safe_title = sanitize_title(title)
      local filename = string.format("%04d_%s_%s.md", note_number, selected_type, safe_title)
      local target_path = utils.join(config.root_path, config.folders.consolidated, filename)
      utils.ensure_dir(vim.fn.fnamemodify(target_path, ":h"))

      -- Prevent overwrite
      if vim.fn.filereadable(target_path) == 1 then
         vim.notify("Cannot import: ID collision or file exists (" .. filename .. ")", vim.log.levels.ERROR)
         return
      end

      -- Generate New Frontmatter
      local template_type = (selected_type == "bib") and "bibliography" or
      selected_type == "agg" and "agg" or "note"

      local new_fm_lines = yaml.create_frontmatter(template_type, fm_data)
      
      -- Construct Final Content
      local final_content = {}
      for _, l in ipairs(new_fm_lines) do table.insert(final_content, l) end
      
      -- Append original body (skip original FM if it existed)
      local start_line = existing_fm and content_start or 1
      for i = start_line, #current_lines do
        table.insert(final_content, current_lines[i])
      end

      -- Write File
      vim.fn.writefile(final_content, target_path)
      require('pkm.index').invalidate(target_path)

      if current_path ~= "" and vim.fn.filereadable(current_path) == 1 then
        vim.ui.select({"Delete original", "Keep original"}, { prompt = "Import successful. Original file:" }, function(choice)
            if choice == "Delete original" then
                vim.fn.delete(current_path)
                require('pkm.index').invalidate(current_path)
            end
            vim.cmd("edit " .. vim.fn.fnameescape(target_path))
        end)
      else
        vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      end

      vim.notify("Imported: " .. filename, vim.log.levels.INFO)
    end)
  end)
end

return M
