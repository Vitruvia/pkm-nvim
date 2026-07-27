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
--   --leader=<key>       Leader key for the plugin's `<leader>…` mappings.
--                        Defaults to a space, matching the author's real
--                        config, so a smoke session exercises the keymaps as
--                        they are actually typed. `space`, `bs`/`backslash`
--                        and `comma` are spelled out because argv cannot
--                        carry them; anything else is taken literally.
--   --no-user-env        Skip the author's editor settings and general
--                        keymaps (see SECTION: user env). They are applied by
--                        default: a test that passes only in an environment
--                        the author never edits in has proved less than it
--                        appears to. Pass this to isolate a failure from them.
--
-- Usage examples (from repo root):
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v160_p1.lua" -c "qa!"
--   nvim -u test/min_init.lua -- "--root=P:/Note-Vault/00 - NotesTeste"
--   nvim -u test/min_init.lua -- "--root=P:/Note-Vault/00 - NotesTeste" --with-telescope
--   nvim -u test/min_init.lua -- "--root=/mnt/p/Note-Vault/00 - NotesTeste" --leader=comma
--
-- Quote the whole flag, as above: vault paths contain spaces, and argv would
-- otherwise arrive as three arguments with the flag holding only `P:/Note-Vault/00`.
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
-- SECTION: --leader
-- =============================================================================
--
-- `<leader>` is expanded when a mapping is created, not when it is pressed, so
-- this has to be set **before** pkm.setup() registers anything. Without it the
-- session falls back to Neovim's default `\`, and the keymaps are all there but
-- under a prefix nobody types — which reads as "the keymaps don't work".

local LEADER_WORDS = {
  space     = ' ',
  bs        = '\\',
  backslash = '\\',
  comma     = ',',
}

local leader = FLAGS['leader']
if leader == true or leader == nil then
  leader = ' '   -- the author's habitual leader; smoke as you actually type
else
  leader = LEADER_WORDS[leader:lower()] or leader
end
vim.g.mapleader      = leader
vim.g.maplocalleader = leader

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

-- =============================================================================
-- SECTION: user env — the author's editor settings and general keymaps
-- =============================================================================
--
-- Transcribed from the author's real init.lua so a session here edits the way
-- the author's editor edits. Applied *before* pkm.setup() on purpose: that is
-- the order in the real config too (these are set at the top of init.lua, and
-- Lazy runs pkm's config function afterwards), so where the two ever collide,
-- PKM wins in both places rather than only here.
--
-- Deliberately NOT transcribed, and why:
--   - The shell block (powershell.exe and friends). The plugin never shells
--     out — no vim.fn.system, jobstart or popen anywhere in lua/pkm — so it
--     buys no fidelity and costs a process spawn.
--   - The run-current-file maps (<leader>, <leader>ç <leader>. <leader>;).
--     They invoke py/python/cl on the buffer; nothing about PKM is exercised
--     by them, and a stray keypress in a smoke session would run a compiler.
--   - Plugin configuration (kanagawa, lualine, vimtex, treesitter opts).
--     Those plugins are not on this runtimepath at all.
--   - `autocmd FileType md → setlocal textwidth=80`. It is in the real config
--     and it *never fires*: Neovim gives a .md file the filetype `markdown`,
--     not `md`. Reproducing it faithfully means not setting textwidth here
--     either — which is what the author's markdown buffers actually get.

if not FLAGS['no-user-env'] then
  vim.opt.number         = true
  vim.opt.mouse          = 'a'
  vim.opt.autoread       = true
  vim.opt.ignorecase     = true
  vim.opt.smartcase      = true
  vim.opt.hlsearch       = false
  vim.opt.wrap           = true
  vim.opt.breakindent    = true
  vim.opt.tabstop        = 4
  vim.opt.shiftwidth     = 4
  vim.opt.expandtab      = true
  vim.opt.colorcolumn    = '80'
  vim.opt.swapfile       = false
  -- Not cosmetic: on Windows this decides whether the editor folds case when
  -- comparing filenames, which is the same question notes.is_same_file()
  -- answers with its own platform-gated fallback.
  vim.opt.fileignorecase = false

  local map = vim.keymap.set

  -- Line ends
  map({ 'n', 'x', 'o' }, '<leader>h', '^')
  map({ 'n', 'x', 'o' }, '<leader>l', 'g_')
  map('n', '<F5>', ':e %<enter>')

  -- Clipboard
  map({ 'n', 'x' }, 'cp',  '"+y')
  map({ 'n', 'x' }, 'cp*', '"*y')
  map({ 'n', 'x' }, 'cv',  '"+p')

  -- Delete without clobbering the unnamed register
  map({ 'n', 'x' }, 'x', '"_x')

  -- Windows. Note that j/k become display-line motions: with wrap on, a
  -- wrapped line takes more than one press to cross. Any test that counts
  -- j presses over PKM's own panels is measuring the wrong thing.
  map({ 'n', 'x' }, '<C-s>', ':vsplit<enter>')
  map({ 'n', 'x' }, '<C-x>', ':close<enter>')
  map({ 'n', 'x' }, '<C-l>', '<C-w>l')
  map({ 'n', 'x' }, '<C-h>', '<C-w>h')
  map({ 'n', 'x' }, '<C-j>', '<C-w>j')
  map({ 'n', 'x' }, '<C-k>', '<C-w>k')
  map({ 'n', 'x' }, 'j', 'gj')
  map({ 'n', 'x' }, 'k', 'gk')

  -- Terminal mode
  map({ 't', 'x' }, '<C-s>', '<C-\\><C-N>:vsplit<enter>')
  map({ 't', 'x' }, '<C-x>', '<C-\\><C-N>:close<enter>')
  map({ 't', 'x' }, '<C-l>', '<C-\\><C-N><C-w>l')
  map({ 't', 'x' }, '<C-h>', '<C-\\><C-N><C-w>h')
  map({ 't', 'x' }, '<C-j>', '<C-\\><C-N><C-w>j')
  map({ 't', 'x' }, '<C-k>', '<C-\\><C-N><C-w>k')
  map({ 't', 'x' }, '<Esc>', '<C-\\><C-N>')

  -- Buffers
  map('n', '<leader>w',  '<cmd>write<cr>')
  map('n', '<leader>W',  '<cmd>write!<cr>')
  map('n', '<leader>bq', '<cmd>bdelete<cr>')
  map('n', '<leader>bl', '<cmd>buffers<cr>')

  -- Highlight on yank, from the author's user_cmds group.
  local ugroup = vim.api.nvim_create_augroup('pkm_test_user_env', { clear = true })
  vim.api.nvim_create_autocmd('TextYankPost', {
    desc = 'Highlight on yank',
    group = ugroup,
    callback = function()
      vim.hl.on_yank({ higroup = 'Visual', timeout = 200 })
    end,
  })
  vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'help', 'man' },
    group   = ugroup,
    command = 'nnoremap <buffer> q <cmd>quit<cr>',
  })
end

require('pkm').setup({
  root_path = root_path,
})
