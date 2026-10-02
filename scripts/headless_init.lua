-- =============================================================================
-- scripts/headless_init.lua — the official init for driving pkm.api headless
-- =============================================================================
-- The init an assistant or script passes with `-u` to call `require('pkm.api')`
-- from `nvim --headless`. It exists because the obvious minimal init —
-- `require('pkm').setup({ root_path = … })` with only pkm-nvim on the
-- runtimepath — half-works: `create`/`find`/`read` succeed, and the section
-- writers (`insert_section`, `cite_source`, `annotate` with a heading) then
-- fail, because they need the pkm-markdown sibling. This init mounts the whole
-- suite and refuses to start on an incomplete one.
--
-- What it does, in order:
--   1. Puts the three suite plugins on the runtimepath — pkm-nvim (this repo),
--      pkm-markdown and pkm-syntax — resolved as SIBLINGS of this repo, which is
--      the layout of both the development tree (P:/Active/pkm-suite/…) and a
--      Lazy.nvim install (<data>/lazy/pkm-nvim, …/pkm-markdown, …/pkm-syntax).
--      `--pkm-suite=<dir>` names another parent directory.
--   2. Requires the vault: `--root=<path>` must name an existing directory.
--      There is no fallback — an operation never guesses its vault, and a
--      silent default is a write into the wrong one.
--   3. Never reads or writes the user's ShaDa (marks, registers, history), and
--      creates no swap file (v1.85.0 P2): a headless session never leaves a
--      `.swp` behind that another Neovim would read as "this note is being
--      edited" — and the `--root=…` argument, which nvim's `-c` form also opens
--      as an empty buffer, no longer trips E303 on a path it cannot name.
--   4. Calls `require('pkm').setup({ root_path = root })`, then
--      `require('pkm.api').health()`, and exits non-zero if it is not ok.
--
-- Every failure writes one line to stderr and exits with status 1, so a caller
-- that checks the exit code never mistakes a broken session for an empty answer.
--
-- Usage (flags go after a literal `--`; quote the whole flag — vault paths
-- contain spaces):
--
--   # a task in a file — the recommended form (v1.85.0 P2): `-l` runs the script
--   # and exits 1 on ANY Lua error; no shell quoting of Lua, no length limit
--   nvim -u "<pkm-nvim>/scripts/headless_init.lua" -l task.lua \
--     -- "--root=P:/Note-Vault/02 - LLM-Claude"
--
--   # a one-liner (a Lua error here still exits 0 — read stderr)
--   nvim --headless -u "<pkm-nvim>/scripts/headless_init.lua" \
--     -c "lua require('pkm.api').emit(require('pkm.api').structure())" \
--     -c "qa!" -- "--root=P:/Note-Vault/02 - LLM-Claude"
--
-- The traps of the `-c` form (wikilinks closing a `[[…]]` long string, E5107,
-- Windows stdout decoding) are in doc/PKM_API.md § Headless pitfalls.
--
-- Flags:
--   --root=<path>        REQUIRED. The vault this session operates on.
--   --pkm-suite=<dir>    Optional. The directory holding pkm-nvim, pkm-markdown
--                        and pkm-syntax. Default: this repo's parent directory.
-- =============================================================================

--- Write one line to stderr and stop with status 1.
---@param msg string
local function die(msg)
  io.stderr:write('[pkm headless_init] ' .. msg .. '\n')
  os.exit(1)
end

-- =============================================================================
-- SECTION: Flags (argv after a literal `--`, left to the script by nvim)
-- =============================================================================

local FLAGS = {}
do
  local after = false
  for _, arg in ipairs(vim.v.argv) do
    if after then
      local key, val = arg:match('^%-%-([%w%-]+)=(.*)$')
      if key then
        FLAGS[key] = val
      else
        local bare = arg:match('^%-%-([%w%-]+)$')
        if bare then FLAGS[bare] = true end
      end
    elseif arg == '--' then
      after = true
    end
  end
end

-- =============================================================================
-- SECTION: Runtimepath — the three suite plugins
-- =============================================================================

local this_file = debug.getinfo(1, 'S').source:sub(2)          -- strip the '@'
local repo_root = vim.fn.fnamemodify(this_file, ':p:h:h')      -- scripts/ -> repo
local suite     = FLAGS['pkm-suite']
if type(suite) ~= 'string' or suite == '' then
  suite = vim.fn.fnamemodify(repo_root, ':h')
end
suite = vim.fn.fnamemodify(suite, ':p'):gsub('[/\\]+$', '')

-- pkm-nvim is this repo, wherever it is checked out (its folder name may differ
-- from `pkm-nvim`); the two siblings are looked up by name under the suite dir.
local plugins = {
  { name = 'pkm-nvim',     dir = repo_root },
  { name = 'pkm-markdown', dir = suite .. '/pkm-markdown' },
  { name = 'pkm-syntax',   dir = suite .. '/pkm-syntax' },
}
for _, p in ipairs(plugins) do
  if vim.fn.isdirectory(p.dir) == 0 then
    die(p.name .. ' not found at ' .. p.dir
      .. ' (pass --pkm-suite=<dir> naming the directory that holds the three plugins)')
  end
  vim.opt.runtimepath:prepend(p.dir)
end

-- Never touch the user's ShaDa; also avoids E138 from rapid successive runs.
vim.o.shadafile = 'NONE'

-- No swap files: a headless call must not look like an editor holding a note
-- open (a `.swp` is how one Neovim tells another a file is being edited).
vim.o.swapfile = false

-- =============================================================================
-- SECTION: The vault — required, never guessed
-- =============================================================================

local root = FLAGS['root']
if type(root) ~= 'string' or root == '' then
  die('--root=<path> is required (the vault this session operates on)')
end
if vim.fn.isdirectory(root) == 0 then
  die('--root is not an existing directory: ' .. root)
end

require('pkm').setup({ root_path = root })

-- =============================================================================
-- SECTION: Preflight — refuse an incomplete session
-- =============================================================================

local health = require('pkm.api').health()
if not health.ok then
  die('incomplete session: ' .. table.concat(health.errors, '; '))
end
