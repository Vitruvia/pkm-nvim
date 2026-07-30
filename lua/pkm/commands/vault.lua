-- =============================================================================
-- pkm.commands.vault — the vault registry lifecycle
-- =============================================================================
-- Dependencies : pkm.vault, pkm.picker (lazy, inside handlers)
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- A vault is a folder; the registry beside the vaults is what gives it a
-- number and a name, and the folder `NN - Name` is derived from that pair.
-- So renaming and renumbering *are* moves, and neither touches a note — which
-- is why none of these commands has anything to say about note contents.
--
-- Only unregistering confirms. It is the one operation here that moves a
-- whole vault out of the set; the rest are reversible by their opposite.
--
-- Public API:
--   register() → register this context's :PKM* commands
-- =============================================================================

local M = {}

function M.register()

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

  --- Folder names :PKMVaultAdopt can take: everything under Unregistered/, and
  --- every folder beside the vaults that no vault claims.
  ---
  --- The second half is how a vault that predates the registry gets into it —
  --- the first `:PKMVaultAdopt "01 - Vitruvia"` on a Note-Vault that has no
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

  vim.api.nvim_create_user_command('PKMVault', function(opts)
    local vault = require('pkm.vault')

    -- `!` also makes it the vault that opens next time. A bang rather than a
    -- command of its own: "go there, and stay there" is one decision, taken
    -- where the switch is already being made, and the registry is where the
    -- answer has to live — a name in init.lua cannot survive a rename, because
    -- a rename never reads init.lua.
    local function switch(name)
      local ok, err, entry = vault.select(name)
      if not ok then
        vim.notify('[pkm] ' .. (err or 'the vault was not changed'), vim.log.levels.ERROR)
        return
      end

      local msg = 'active vault: ' .. vault.folder_of(entry)
      if opts.bang then
        local ok_def, err_def = vault.set_default(entry.name)
        msg = ok_def and (msg .. ' — and it is now the default')
                      or (msg .. ' — but the default was not saved: ' .. tostring(err_def))
      end
      vim.notify('[pkm] ' .. msg, vim.log.levels.INFO)
    end

    local name = vim.trim(opts.args)
    if name ~= '' then
      switch(name)
      return
    end

    local entries = vault.list()
    if #entries == 0 then
      vim.notify('[pkm] no vaults are registered — :PKMVaultNew makes one', vim.log.levels.INFO)
      return
    end

    -- Listing and switching are one panel, and the panel answers "which one am
    -- I in?" before it asks "which one do you want?".
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
  end, {
    nargs    = '?',
    bang     = true,
    complete = function() return vault_names() end,
    desc     = 'Switch the active vault (no argument lists them; ! also makes it the default)',
  })

  vim.api.nvim_create_user_command('PKMVaultNew', function(opts)
    local vault = require('pkm.vault')
    local name  = vim.trim(opts.args)

    local function make(n)
      local ok, err = vault.create(n, { git = not opts.bang })
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
  end, {
    nargs = '?',
    bang  = true,
    desc  = 'Create a vault: folder, skeleton and registry entry (! for no git repository)',
  })

  vim.api.nvim_create_user_command('PKMVaultRename', function(opts)
    local from, to = opts.fargs[1], opts.fargs[2]
    if not from or not to then
      vim.notify('[pkm] :PKMVaultRename <from> <to>', vim.log.levels.WARN)
      return
    end
    local ok, err = require('pkm.vault').rename(from, to)
    vault_done(ok, err, string.format('%s is now named %s', from, to))
  end, {
    nargs    = '+',
    complete = function(_, line)
      -- Only the first argument is a vault: the second is the new name, and
      -- completing an existing vault there would offer exactly the collision
      -- the rename refuses.
      return #vim.split(vim.trim(line), '%s+') > 2 and {} or vault_names()
    end,
    desc = 'Rename a vault, keeping its number (the folder moves; no note changes)',
  })

  vim.api.nvim_create_user_command('PKMVaultRenumber', function(opts)
    local name, n = opts.fargs[1], tonumber(opts.fargs[2])
    if not name or not n then
      vim.notify('[pkm] :PKMVaultRenumber <name> <number>', vim.log.levels.WARN)
      return
    end
    local ok, err = require('pkm.vault').renumber(name, n)
    vault_done(ok, err, string.format('%s is now vault %02d', name, n))
  end, {
    nargs    = '+',
    complete = function(_, line)
      return #vim.split(vim.trim(line), '%s+') > 2 and {} or vault_names()
    end,
    desc = 'Renumber a vault, keeping its name (the folder moves; no note changes)',
  })

  vim.api.nvim_create_user_command('PKMVaultUnregister', function(opts)
    local vault = require('pkm.vault')

    local function ask(name)
      local entry = vault.get(name)
      if not entry then
        vim.notify(string.format('[pkm] no vault is named %q', name), vim.log.levels.ERROR)
        return
      end
      -- Confirmed even with a direct argument: this is the one command that
      -- takes a whole vault out of the set.
      require('pkm.picker').confirm({
        title = 'Unregister vault ' .. vault.folder_of(entry) .. '?',
        lines = {
          'The folder moves, intact, to:',
          '',
          '    ' .. tostring(vault.unregistered_dir()) .. '/' .. entry.name,
          '',
          'No note is deleted, and :PKMVaultAdopt ' .. entry.name .. ' is the way back.',
          'Until it is adopted its notes belong to no vault.',
        },
        on_confirm = function()
          local ok, err = vault.unregister(entry.name)
          vault_done(ok, err, entry.name .. ' moved to Unregistered/')
        end,
      })
    end

    local name = vim.trim(opts.args)
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
  end, {
    nargs    = '?',
    complete = function() return vault_names() end,
    desc     = 'Move a vault out of the registry into Unregistered/ (always confirms)',
  })

  vim.api.nvim_create_user_command('PKMVaultAdopt', function(opts)
    local vault = require('pkm.vault')

    local function take(folder)
      local ok, err, entry = vault.adopt(folder)
      vault_done(ok, err, string.format('%s adopted as %s', folder,
        entry and vault.folder_of(entry) or folder))
    end

    local folder = vim.trim(opts.args)
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
  end, {
    nargs    = '?',
    complete = adoptable,
    desc     = 'Register a folder from Unregistered/ as a vault, contents untouched',
  })

end

return M
