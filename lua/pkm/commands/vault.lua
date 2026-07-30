-- =============================================================================
-- pkm.commands.vault — the vault registry lifecycle
-- =============================================================================
-- Dependencies : pkm.args, pkm.vault, pkm.picker (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- A vault is a folder; the registry beside the vaults is what gives it a
-- number and a name, and the folder `NN - Name` is derived from that pair.
-- So renaming and renumbering *are* moves, and neither touches a note — which
-- is why none of these commands has anything to say about note contents.
--
-- `:PKMVault <verb>`: a bare name (or no argument) switches or lists, and the
-- verbs are new, rename, renumber, unregister, adopt. `!` means "make it the
-- default" on a switch and "no git repository" on new. Only unregistering
-- confirms — it is the one operation that moves a whole vault out of the set.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local function vault_names()
  local names = {}
  for _, v in ipairs(require('pkm.vault').list()) do names[#names + 1] = v.name end
  return names
end

--- Report an (ok, err) pair from pkm.vault in one place.
local function vault_done(ok, err, success_msg)
  if ok then
    vim.notify('[pkm] ' .. success_msg, vim.log.levels.INFO)
  else
    vim.notify('[pkm] ' .. (err or 'the vault was not changed'), vim.log.levels.ERROR)
  end
end

--- Folder names adopt can take: everything under Unregistered/, and every folder
--- beside the vaults that no vault claims.
---
--- The second half is how a vault that predates the registry gets into it — the
--- first `:PKMVault adopt "01 - Vitruvia"` on a Note-Vault that has no
--- vaults.json yet. Offering only Unregistered/ left that path working but
--- invisible, which for a first use is the same as missing.
local function adoptable()
  local vault = require('pkm.vault')
  local roots = { vault.unregistered_dir(), vault.vaults_root() }

  local out, seen = {}, {}
  for _, dir in ipairs(roots) do
    for _, path in ipairs(vim.fn.glob(dir .. '/*', false, true)) do
      local leaf = vim.fn.fnamemodify(path, ':t')
      if vim.fn.isdirectory(path) == 1
      and leaf ~= 'Unregistered'
      and not seen[leaf]
      and vault.of(path) == nil then
        seen[leaf]  = true
        out[#out + 1] = leaf
      end
    end
  end
  return out
end

--- Switch the active vault (a bare name), or list them when name is empty. With
--- make_default, the switch also becomes the vault that opens next time.
local function act_vault_switch(name_str, make_default)
  local vault = require('pkm.vault')

  local function switch(name)
    local ok, err, entry = vault.select(name)
    if not ok then
      vim.notify('[pkm] ' .. (err or 'the vault was not changed'), vim.log.levels.ERROR)
      return
    end
    local msg = 'active vault: ' .. vault.folder_of(entry)
    if make_default then
      local ok_def, err_def = vault.set_default(entry.name)
      msg = ok_def and (msg .. ' — and it is now the default')
                    or (msg .. ' — but the default was not saved: ' .. tostring(err_def))
    end
    vim.notify('[pkm] ' .. msg, vim.log.levels.INFO)
  end

  local name = vim.trim(name_str or '')
  if name ~= '' then
    switch(name)
    return
  end

  local entries = vault.list()
  if #entries == 0 then
    vim.notify('[pkm] no vaults are registered — :PKMVault new makes one', vim.log.levels.INFO)
    return
  end

  -- Listing and switching are one panel, and the panel answers "which one am I
  -- in?" before it asks "which one do you want?".
  local active  = vault.active()
  local default = vault.default()
  require('pkm.picker').choose(entries, {
    title   = 'Vault · ' .. (vault.indicator() ~= '' and vault.indicator() or 'unregistered root'),
    display = function(row)
      local here = active  and active.number  == row.number
      local dflt = default and default.number == row.number
      -- ● where you are, ★ what opens next time; they are different questions
      -- and a list that answered only the first would invite the wrong one.
      return (here and '●' or ' ') .. (dflt and '★' or ' ') .. ' ' .. vault.folder_of(row)
    end,
  }, function(row) switch(row.name) end)
end

--- Create a vault (folder, skeleton, registry entry); no_git skips the repo.
local function act_vault_new(name_str, no_git)
  local vault = require('pkm.vault')
  local name  = vim.trim(name_str or '')

  local function make(n)
    local ok, err = vault.create(n, { git = not no_git })
    vault_done(ok, err, string.format('vault %s created',
      ok and vault.folder_of(vault.get(n)) or n))
  end

  if name ~= '' then
    make(name)
    return
  end
  vim.ui.input({ prompt = 'New vault name: ' }, function(input)
    if input and vim.trim(input) ~= '' then make(vim.trim(input)) end
  end)
end

--- Rename a vault, keeping its number (the folder moves; no note changes).
local function act_vault_rename(from, to)
  if not from or not to then
    vim.notify('[pkm] :PKMVault rename <from> <to>', vim.log.levels.WARN)
    return
  end
  local ok, err = require('pkm.vault').rename(from, to)
  vault_done(ok, err, string.format('%s is now named %s', from, to))
end

--- Renumber a vault, keeping its name (the folder moves; no note changes).
local function act_vault_renumber(name, n)
  if not name or not n then
    vim.notify('[pkm] :PKMVault renumber <name> <number>', vim.log.levels.WARN)
    return
  end
  local ok, err = require('pkm.vault').renumber(name, n)
  vault_done(ok, err, string.format('%s is now vault %02d', name, n))
end

--- Move a vault out of the registry into Unregistered/ (always confirms).
local function act_vault_unregister(name_str)
  local vault = require('pkm.vault')

  local function ask(name)
    local entry = vault.get(name)
    if not entry then
      vim.notify(string.format('[pkm] no vault is named %q', name), vim.log.levels.ERROR)
      return
    end
    -- Confirmed even with a direct argument: this is the one command that takes
    -- a whole vault out of the set.
    require('pkm.picker').confirm({
      title = 'Unregister vault ' .. vault.folder_of(entry) .. '?',
      lines = {
        'The folder moves, intact, to:',
        '',
        '    ' .. tostring(vault.unregistered_dir()) .. '/' .. entry.name,
        '',
        'No note is deleted, and :PKMVault adopt ' .. entry.name .. ' is the way back.',
        'Until it is adopted its notes belong to no vault.',
      },
      on_confirm = function()
        local ok, err = vault.unregister(entry.name)
        vault_done(ok, err, entry.name .. ' moved to Unregistered/')
      end,
    })
  end

  local name = vim.trim(name_str or '')
  if name ~= '' then
    ask(name)
    return
  end

  local entries = vault.list()
  if #entries == 0 then
    vim.notify('[pkm] no vaults are registered', vim.log.levels.INFO)
    return
  end
  require('pkm.picker').choose(entries, {
    title   = 'Unregister which vault?',
    display = function(row) return vault.folder_of(row) end,
  }, function(row) ask(row.name) end)
end

--- Register a folder from Unregistered/ as a vault, contents untouched.
local function act_vault_adopt(folder_str)
  local vault = require('pkm.vault')

  local function take(folder)
    local ok, err, entry = vault.adopt(folder)
    vault_done(ok, err, string.format('%s adopted as %s', folder,
      entry and vault.folder_of(entry) or folder))
  end

  local folder = vim.trim(folder_str or '')
  if folder ~= '' then
    take(folder)
    return
  end

  local folders = adoptable()
  if #folders == 0 then
    vim.notify('[pkm] nothing in Unregistered/ to adopt', vim.log.levels.INFO)
    return
  end
  require('pkm.picker').choose(folders, {
    title   = 'Adopt which folder?',
    display = tostring,
  }, take)
end

local M = {}

function M.register()

  -- ---------------------------------------------------------------------------
  -- :PKMVault — the context form
  -- ---------------------------------------------------------------------------
  local VAULT_VERBS = { 'new', 'rename', 'renumber', 'unregister', 'adopt' }

  vim.api.nvim_create_user_command('PKMVault', function(opts)
    local p = require('pkm.args').parse(opts, { verbs = VAULT_VERBS })
    local v = p.verb
    if v == 'new' then
      act_vault_new(table.concat(vim.list_slice(p.positional, 1), ' '), opts.bang)
    elseif v == 'rename' then
      act_vault_rename(p.positional[1], p.positional[2])
    elseif v == 'renumber' then
      act_vault_renumber(p.positional[1], tonumber(p.positional[2]))
    elseif v == 'unregister' then
      act_vault_unregister(table.concat(vim.list_slice(p.positional, 1), ' '))
    elseif v == 'adopt' then
      act_vault_adopt(table.concat(vim.list_slice(p.positional, 1), ' '))
    else
      -- No verb: the whole argument is a vault name to switch to (or nothing,
      -- which lists them). opts.args preserves a spaced name.
      act_vault_switch(opts.args, opts.bang)
    end
  end, {
    nargs    = '*',
    bang     = true,
    complete = function(arg_lead, line)
      local words = vim.split(vim.trim(line), '%s+')
      local nword = #words
      local verb  = (words[2] or ''):lower()
      local function filt(list)
        local lead = (arg_lead or ''):lower()
        return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, list)
      end
      if nword <= 2 then
        local out = { 'new', 'rename', 'renumber', 'unregister', 'adopt' }
        vim.list_extend(out, vault_names())
        return filt(out)
      elseif verb == 'adopt' then
        return filt(adoptable())
      elseif (verb == 'rename' or verb == 'renumber' or verb == 'unregister') and nword == 3 then
        return filt(vault_names())
      end
      return {}
    end,
    desc     = 'Vaults: :PKMVault [<name>] | new|rename|renumber|unregister|adopt (! = default/no-git)',
  })

end

return M
