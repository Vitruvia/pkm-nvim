-- =============================================================================
-- pkm.commands.agent — the agent-protocol / skill commands
-- =============================================================================
-- Dependencies : pkm.args, pkm.skill
-- Consumed by  : pkm.commands (init) → registered during setup
--
-- `:PKMAgentProtocol <verb>` — install / update / path. Installs the pkm-notes
-- skill (skills/pkm-notes/SKILL.md plus the protocol and API docs it cites) into
-- the user's Claude Code skills directory, so an assistant reaches for pkm.api by
-- default. `update` is `install`; `path` reports the source and destination.
--
-- Public API:
--   register() → register this context's :PKM* command
-- =============================================================================

local M = {}

function M.register()

  local VERBS = { 'install', 'update', 'path' }

  vim.api.nvim_create_user_command('PKMAgentProtocol', function(opts)
    local p = require('pkm.args').parse(opts, {
      verbs = VERBS, default = 'install', named = false,
    })
    local skill = require('pkm.skill')

    -- A custom destination may contain spaces, so take it from the raw fargs
    -- rather than the space-split positional.
    local dest = table.concat(vim.list_slice(opts.fargs, p.is_verb and 2 or 1), ' ')
    dest = dest ~= '' and dest or nil

    if p.verb == 'install' or p.verb == 'update' then
      local res = skill.install(dest)
      if not res.ok then
        vim.notify('[pkm] skill install failed: ' .. (res.error or 'unknown error'),
          vim.log.levels.ERROR)
        return
      end
      local msg = string.format('[pkm] skill %s → %s (%s)',
        p.verb, res.dest, table.concat(res.files, ', '))
      -- On the real install (no custom destination), also place the
      -- /pkm-learning slash command in the user's commands directory.
      if not dest then
        local cres = skill.install_command()
        msg = msg .. (cres.ok and ('; command → ' .. cres.dir)
          or ('; command FAILED: ' .. (cres.error or '?')))
      end
      vim.notify(msg, vim.log.levels.INFO)
    elseif p.verb == 'path' then
      vim.notify(string.format(
        '[pkm] skill source: %s\n         skill dest:   %s\n         command dest: %s',
        skill.source_dir() or '(not found on runtimepath)',
        skill.default_dest(), skill.default_commands_dest()),
        vim.log.levels.INFO)
    end
  end, {
    nargs = '*',
    complete = function(arg_lead)
      local lead = (arg_lead or ''):lower()
      return vim.tbl_filter(function(t) return t:lower():find(lead, 1, true) == 1 end, VERBS)
    end,
    desc = 'The agent skill: :PKMAgentProtocol install|update|path; bare = install',
  })

end

return M
