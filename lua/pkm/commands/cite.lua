-- =============================================================================
-- pkm.commands.cite — citations, and the wikilink navigation around them
-- =============================================================================
-- Dependencies : pkm.citations, pkm.notes, pkm.yaml, pkm.picker, pkm.ui,
--                pkm.telescope (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- The citation graph from the editor's side: insert, cite/uncite by reference,
-- rebuild references, and the link/backlink navigation that rides on it.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- Citations
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMInsertCitation', function()
    local has_tele = pcall(require, 'telescope')
    if has_tele then
      require('pkm.telescope').insert_citation_picker()
    else
      require('pkm.ui').insert_citation_ui()
    end
  end, { desc = 'Insert a citation at cursor (Telescope picker or ui fallback)' })

  vim.api.nvim_create_user_command('PKMGotoCitation', function()
    require('pkm.citations').goto_citation()
  end, {})

  -- The current note is the source; the argument names the target. With no
  -- argument, :PKMCite falls back to the interactive picker (the same one
  -- :PKMInsertCitation opens), keeping the two forms one command. The target
  -- is a note path, an identifier (note-0042) or a token (note[0042]).
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

  vim.api.nvim_create_user_command('PKMCite', function(opts)
    local citations = require('pkm.citations')
    if opts.args == '' then
      if pcall(require, 'telescope') then
        require('pkm.telescope').insert_citation_picker()
      else
        require('pkm.ui').insert_citation_ui()
      end
      return
    end
    local source = current_note()
    if not source then return end
    local ok, err = citations.cite(source, opts.args)
    if ok then
      vim.notify('[pkm] cited ' .. opts.args, vim.log.levels.INFO)
    else
      vim.notify('[pkm] ' .. (err or 'not cited'), vim.log.levels.ERROR)
    end
  end, {
    nargs = '?',
    desc  = 'Cite a note from the current one (picker if no argument)',
  })

  vim.api.nvim_create_user_command('PKMUncite', function(opts)
    local citations = require('pkm.citations')
    local source = current_note()
    if not source then return end

    local function remove(ref)
      local ok, n, err = citations.uncite(source, ref)
      if ok then
        vim.notify(string.format('[pkm] removed %d citation%s of %s',
          n, n == 1 and '' or 's', ref), vim.log.levels.INFO)
      else
        vim.notify('[pkm] ' .. (err or 'not removed'), vim.log.levels.ERROR)
      end
    end

    if opts.args ~= '' then
      remove(opts.args)
      return
    end

    -- No argument: choose from what this note currently cites.
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
  end, {
    nargs = '?',
    desc  = 'Remove a citation from the current note (picker if no argument)',
  })

  vim.api.nvim_create_user_command('PKMUpdateReferences', function()
    require('pkm.citations').update_references()
  end, {})

  -- ---------------------------------------------------------------------------
  -- Navigation and linking
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_user_command('PKMLinkNote', function()
    require('pkm.notes').link_to_note()
  end, {})

  vim.api.nvim_create_user_command('PKMFollowLink', function()
    require('pkm.notes').follow_link()
  end, {})

  vim.api.nvim_create_user_command('PKMBacklinks', function()
    require('pkm.notes').show_backlinks()
  end, {})

end

return M
