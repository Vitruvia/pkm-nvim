-- test/min_init.lua
-- Minimal, isolated init for headless (or interactive) PKM.nvim testing.
--
-- Deliberately does NOT load the user's real Neovim config, init.lua, or
-- Lazy-managed plugin copy by default — points runtimepath directly at THIS
-- repo's own lua/ directory, resolved from this file's own location, so it
-- works regardless of the shell's current working directory and always
-- exercises the local working tree about to be committed, not whatever is
-- currently installed via Lazy.
--
-- Optional flags, passed after a literal `--` (Neovim's own convention:
-- everything past `--` is left in v:argv for the script, never interpreted
-- by nvim itself):
--
--   --root=<path>        Use <path> as root_path instead of a disposable
--                        temp directory. Point this at a real (or copied)
--                        Notes tree for manual smoke testing with real
--                        data; leave unset for automated tests, which
--                        should never touch the live Notes tree.
--   --with-telescope     Add plenary.nvim and telescope.nvim to the
--                        runtimepath from the standard Lazy data directory
--                        (stdpath('data')/lazy/<name>), making the
--                        Telescope-enabled code paths reachable too.
--                        Requires both already installed via Lazy in your
--                        real config — this only makes them *visible* to
--                        this isolated session, it doesn't install them.
--                        Omit this flag to test the float/no-Telescope
--                        fallback paths (the default, and what every
--                        automated test file in this repo assumes so far).
--
-- Usage examples (from repo root):
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v160_p1.lua" -c "qa!"
--   nvim -u test/min_init.lua -- --root=/mnt/p/Notes
--   nvim -u test/min_init.lua -- --root=/mnt/p/Notes --with-telescope
--
-- Extending: add new flags by reading FLAGS['your-flag-name'] wherever
-- needed below (or in a new SECTION). parse_flags() itself needs no
-- changes for ordinary --name / --name=value flags — only a genuinely new
-- flag *shape* (e.g. a repeated/list flag) would require touching it.

local this_file = debug.getinfo(1, "S").source:sub(2)   -- strip leading '@'
local repo_root = vim.fn.fnamemodify(this_file, ':p:h:h')  -- test/min_init.lua -> repo root

vim.opt.runtimepath:prepend(repo_root)

-- Disposable test run: never read or write the user's real ShaDa file
-- (marks, registers, command/search history, oldfiles). Equivalent to
-- passing -i NONE on the command line, set here so it applies automatically
-- without editing the invocation. Also sidesteps E138 (all ShaDa temp-file
-- suffixes exhausted) from repeated rapid headless invocations never
-- completing their atomic write+rename.
vim.o.shadafile = 'NONE'

-- =============================================================================
-- SECTION: Flag parsing
-- =============================================================================

--- Parse flags from the argv segment after a literal `--`.
--- Supports `--name` (boolean true) and `--name=value` (string value).
---@return table<string, string|boolean>
local function parse_flags()
  local flags = {}
  local after_dashdash = false
  for _, arg in ipairs(vim.v.argv) do
    if after_dashdash then
      local key, val = arg:match('^%-%-([%w%-]+)=(.*)$')
      if key then
        flags[key] = val
      else
        local bare = arg:match('^%-%-([%w%-]+)$')
        if bare then flags[bare] = true end
      end
    elseif arg == '--' then
      after_dashdash = true
    end
  end
  return flags
end

local FLAGS = parse_flags()

-- =============================================================================
-- SECTION: --with-telescope
-- =============================================================================

if FLAGS['with-telescope'] then
  local lazy_root = vim.fn.stdpath('data') .. '/lazy'
  local needed     = { 'plenary.nvim', 'telescope.nvim' }
  local missing    = {}
  for _, name in ipairs(needed) do
    local path = lazy_root .. '/' .. name
    if vim.fn.isdirectory(path) == 1 then
      vim.opt.runtimepath:append(path)
    else
      missing[#missing + 1] = path
    end
  end
  if #missing > 0 then
    vim.notify(
      '[pkm test] --with-telescope: not found, skipping: '
        .. table.concat(missing, ', '),
      vim.log.levels.WARN)
  end
end

-- =============================================================================
-- SECTION: --root
-- =============================================================================

local root_path
if FLAGS['root'] then
  root_path = FLAGS['root']
  if vim.fn.isdirectory(root_path) == 0 then
    vim.notify('[pkm test] --root=' .. root_path .. ' does not exist', vim.log.levels.ERROR)
  end
else
  -- Disposable scratch corpus — never the real Notes tree, per the
  -- Standing Verification Protocol. Fresh temp directory every run.
  root_path = vim.fn.tempname()
  vim.fn.mkdir(root_path, 'p')
end

require('pkm').setup({
  root_path = root_path,
})
