-- =============================================================================
-- pkm.skill — install the pkm-notes agent skill
-- =============================================================================
-- Dependencies : pkm.utils
-- Consumed by  : pkm.commands.agent (:PKMAgentProtocol install|update)
--
-- The pkm-notes skill (skills/pkm-notes/SKILL.md) points an assistant at pkm.api
-- so it operates the vault through the surface instead of editing files. Its
-- canonical copy is versioned in this repo; installing copies it, together with
-- the protocol and API-reference docs it cites, into the user's Claude Code
-- skills directory so the bundle is self-contained. The skill receives no vault
-- path — it discovers vaults through the registry at call time.
--
-- Public API:
--   source_dir()            → the installed plugin's skills/pkm-notes dir, or nil
--   default_dest()          → ~/.claude/skills/pkm-notes
--   default_commands_dest() → ~/.claude/commands
--   install(dest)           → copy the skill bundle into dest (default: above)
--   install_command(dir)    → copy the /pkm-learning slash command into dir
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

--- Locate the plugin's skill source and root on the runtimepath.
---@return table|nil  { skill_md, skill_dir, root }
local function plugin_paths()
  local hits = vim.api.nvim_get_runtime_file('skills/pkm-notes/SKILL.md', false)
  if not hits or not hits[1] then return nil end
  local skill_md = hits[1]
  return {
    skill_md  = skill_md,
    skill_dir = vim.fn.fnamemodify(skill_md, ':h'),
    root      = vim.fn.fnamemodify(skill_md, ':h:h:h'), -- out of skills/pkm-notes
  }
end

--- The installed plugin's skills/pkm-notes directory, or nil if not found.
---@return string|nil
function M.source_dir()
  local p = plugin_paths()
  return p and p.skill_dir or nil
end

--- The default install destination: the user's Claude Code skills directory.
---@return string
function M.default_dest()
  return utils.join(vim.fn.expand('~'), '.claude', 'skills', 'pkm-notes')
end

--- The default destination for the slash command: ~/.claude/commands.
---@return string
function M.default_commands_dest()
  return utils.join(vim.fn.expand('~'), '.claude', 'commands')
end

--- Install the /pkm-learning slash command into `dir` (default: the user's
--- Claude Code commands directory). Separate from the skill bundle because
--- slash commands live in a different Claude Code location.
---@param dir string|nil
---@return table  { ok, dir, file, error? }
function M.install_command(dir)
  local p = plugin_paths()
  if not p then
    return { ok = false, error = 'could not locate the pkm-nvim skill on the runtimepath' }
  end
  local src = utils.join(p.skill_dir, 'commands', 'pkm-learning.md')
  if vim.fn.filereadable(src) == 0 then
    return { ok = false, error = 'missing command source: ' .. src }
  end

  dir = dir or M.default_commands_dest()
  vim.fn.mkdir(dir, 'p')
  if vim.fn.isdirectory(dir) == 0 then
    return { ok = false, error = 'could not create destination: ' .. dir }
  end
  if vim.fn.writefile(vim.fn.readfile(src), utils.join(dir, 'pkm-learning.md')) ~= 0 then
    return { ok = false, error = 'could not write pkm-learning.md' }
  end
  return { ok = true, dir = dir, file = 'pkm-learning.md' }
end

--- Install (or update — the two are identical) the pkm-notes skill into `dest`.
--- Copies SKILL.md and the bundled AGENT_PROTOCOL.md / PKM_API.md / CONVENTIONS.md,
--- overwriting any existing copies, so the installed skill is self-contained and
--- current (SKILL.md points at all three).
---@param dest string|nil  destination dir; defaults to `default_dest()`
---@return table  { ok, dest, files, error? }
function M.install(dest)
  local p = plugin_paths()
  if not p then
    return { ok = false, error = 'could not locate the pkm-nvim skill on the runtimepath' }
  end

  dest = dest or M.default_dest()
  vim.fn.mkdir(dest, 'p')
  if vim.fn.isdirectory(dest) == 0 then
    return { ok = false, error = 'could not create destination: ' .. dest }
  end

  local sources = {
    { p.skill_md,                                        'SKILL.md' },
    { utils.join(p.root, 'doc', 'AGENT_PROTOCOL.md'),    'AGENT_PROTOCOL.md' },
    { utils.join(p.root, 'doc', 'PKM_API.md'),           'PKM_API.md' },
    { utils.join(p.root, 'doc', 'CONVENTIONS.md'),       'CONVENTIONS.md' },
  }

  local copied = {}
  for _, s in ipairs(sources) do
    local src, name = s[1], s[2]
    if vim.fn.filereadable(src) == 0 then
      return { ok = false, dest = dest, files = copied, error = 'missing source: ' .. src }
    end
    if vim.fn.writefile(vim.fn.readfile(src), utils.join(dest, name)) ~= 0 then
      return { ok = false, dest = dest, files = copied, error = 'could not write ' .. name }
    end
    copied[#copied + 1] = name
  end

  return { ok = true, dest = dest, files = copied }
end

return M
