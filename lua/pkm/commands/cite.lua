-- =============================================================================
-- pkm.commands.cite — citations, and the wikilink navigation around them
-- =============================================================================
-- Dependencies : pkm, pkm.args, pkm.citations, pkm.notes, pkm.yaml, pkm.picker,
--                pkm.ui, pkm.telescope (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- The citation graph from the editor's side. `:PKMCite <verb>` — add, remove,
-- goto, insert, update, link, follow, backlinks — with `add` the default verb,
-- so a bare `:PKMCite` opens the picker and `:PKMCite <target>` cites.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

--- The current note's path, or nil (with a message) if the buffer is not a note.
local function current_note()
  local path = vim.fn.expand('%:p')
  local root = require('pkm').config.root_path or ''
  local in_root = path ~= '' and root ~= ''
    and path:gsub('\\', '/'):lower():find(root:gsub('\\', '/'):lower(), 1, true)
  if not in_root or not path:match('%.md$') then
    vim.notify('[pkm] not a PKM note — open one first', vim.log.levels.WARN)
    return nil
  end
  return path
end

--- Open the citation-insertion picker (Telescope, or the ui fallback).
local function act_insert()
  if pcall(require, 'telescope') then
    require('pkm.telescope').insert_citation_picker()
  else
    require('pkm.ui').insert_citation_ui()
  end
end

--- Cite a target from the current note; with no target, the picker. Shared by
--- `:PKMCite` and `:PKMCite add`, so the two forms are one behaviour. The target
--- is a note path, an identifier (note-0042) or a token (note[0042]).
---@param target string|nil
local function act_cite(target)
  if not target then
    act_insert()
    return
  end
  local source = current_note()
  if not source then return end
  local ok, err = require('pkm.citations').cite(source, target)
  if ok then
    vim.notify('[pkm] cited ' .. target, vim.log.levels.INFO)
  else
    vim.notify('[pkm] ' .. (err or 'not cited'), vim.log.levels.ERROR)
  end
end

--- Remove a citation from the current note; with no target, choose from what it
--- cites. The core behind `:PKMCite remove`.
---@param target string|nil
local function act_uncite(target)
  local source = current_note()
  if not source then return end

  local function remove(ref)
    local ok, n, err = require('pkm.citations').uncite(source, ref)
    if ok then
      vim.notify(string.format('[pkm] removed %d citation%s of %s',
        n, n == 1 and '' or 's', ref), vim.log.levels.INFO)
    else
      vim.notify('[pkm] ' .. (err or 'not removed'), vim.log.levels.ERROR)
    end
  end

  if target then
    remove(target)
    return
  end

  -- No target: choose from what this note currently cites.
  local fm = require('pkm.yaml').parse_frontmatter(vim.fn.readfile(source))
  local rows = {}
  for _, group in ipairs({ 'notes', 'bib', 'journal', 'scratch' }) do
    for _, e in ipairs((fm and fm.cites and fm.cites[group]) or {}) do
      rows[#rows + 1] = { identifier = e.identifier, title = e.title }
    end
  end
  if #rows == 0 then
    vim.notify('[pkm] this note cites nothing', vim.log.levels.INFO)
    return
  end
  require('pkm.picker').choose(rows, {
    title   = 'Uncite from this note',
    display = function(r) return string.format('%s  %s', r.identifier, r.title or '') end,
  }, function(r) remove(r.identifier) end)
end

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- :PKMCite — the context form
  -- ---------------------------------------------------------------------------
  local CITE_VERBS = { 'add', 'remove', 'goto', 'insert', 'update', 'link', 'follow', 'backlinks' }

  vim.api.nvim_create_user_command('PKMCite', function(opts)
    local p = require('pkm.args').parse(opts, { verbs = CITE_VERBS, default = 'add' })
    -- The target is free text (a path/identifier/token), taken raw from the
    -- words after the verb.
    local rest = table.concat(vim.list_slice(opts.fargs, p.is_verb and 2 or 1), ' ')
    rest = rest ~= '' and rest or nil

    local v = p.verb
    if v == 'add' then
      act_cite(rest)
    elseif v == 'remove' then
      act_uncite(rest)
    elseif v == 'goto' then
      require('pkm.citations').goto_citation()
    elseif v == 'insert' then
      act_insert()
    elseif v == 'update' then
      require('pkm.citations').update_references()
    elseif v == 'link' then
      require('pkm.notes').link_to_note()
    elseif v == 'follow' then
      require('pkm.notes').follow_link()
    elseif v == 'backlinks' then
      require('pkm.notes').show_backlinks()
    end
  end, {
    nargs    = '*',
    complete = function(arg_lead)
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, CITE_VERBS)
    end,
    desc = 'Citations: :PKMCite [add] <target> | remove | goto | insert | update | link | follow | backlinks',
  })

end

return M
