-- =============================================================================
-- pkm.config — Default configuration and resolution
-- =============================================================================
-- Dependencies : pkm.utils
-- Consumed by  : pkm.init (called once, result passed to all module setup())
--
-- This module is pure data — no side effects, no vim commands, no autocmds.
-- The defaults table defines every supported config key. resolve() merges
-- user config over defaults, normalizes paths, validates, and injects author.
--
-- Public API:
--   resolve(user_config?) → table  Merged and validated config
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: Defaults
-- =============================================================================
local defaults = {
  root_path = nil,

  -- Directory the vaults sit in as siblings, holding `vaults.json` — the
  -- registry that maps a number and a name to each vault folder (pkm.vault).
  --
  -- This is the only absolute path the configuration needs, and it names the
  -- *container*, never a vault: renaming, renumbering, unregistering and
  -- adopting all leave it untouched. Set this and `vault` and no vault root is
  -- written down anywhere.
  --
  -- It is never guessed from root_path. Unset simply means no registry, and
  -- a plain root_path keeps working exactly as it always has.
  vaults_path = nil,

  -- Active vault, by name. **Optional, and normally left unset**: the registry
  -- carries its own default, which is the only reference that survives a
  -- rename — the registry performs renames and can correct itself, while a
  -- name written here cannot, because a rename never reads this file. Set it
  -- only to override the default on one machine or one profile.
  --
  -- Resolution order, most specific first: $PKM_VAULT, then this, then the
  -- registry's default.
  vault = nil,

  folders = {
    consolidated = "03-Consolidated",
    journal      = "02-Journal",
    scratchpad   = "01-Scratchpad",
    templates    = "templates",
  },

  sync = {
    enabled           = true,
    auto_sync_on_save = true,
  },

  frontmatter_templates = {
    note = {
      title = "", author = "", created_on = "ISO8601", last_updated_on = "ISO8601",
      tags = {},
      cites    = { notes = {}, bib = {}, journal = {}, scratch = {} },
      cited_by = { notes = {}, bib = {}, journal = {}, scratch = {} },
    },
    agg = {
      title = "", author = "", created_on = "ISO8601", last_updated_on = "ISO8601",
      tags = {},
      cites    = { notes = {}, bib = {}, journal = {}, scratch = {} },
      cited_by = { notes = {}, bib = {}, journal = {}, scratch = {} },
    },
    bibliography = {
      title = "", source_author = "", created_on = "ISO8601", last_updated_on = "ISO8601",
      tags = {},
      cites    = { notes = {}, bib = {}, journal = {}, scratch = {} },
      cited_by = { notes = {}, bib = {}, journal = {}, scratch = {} },
    },
    journal = {
      created_on = "ISO8601", last_updated_on = "ISO8601", author = "",
      tags = {},
      cites    = { notes = {}, bib = {}, journal = {}, scratch = {} },
      cited_by = { notes = {}, bib = {}, journal = {}, scratch = {} },
    },
    scratchpad = {
      title = "", created_on = "ISO8601", last_updated_on = "ISO8601",
      tags = {},
      cites    = { notes = {}, bib = {}, journal = {}, scratch = {} },
      cited_by = { notes = {}, bib = {}, journal = {}, scratch = {} },
    },
  },

  timestamp = {
    default_format = "full",
    auto_timestamp = true,
  },

  -- Named project views. Each key is a view name; each value is a filter
  -- expression string. Activated with :PKMView <name>.
  -- Example:
  --   projects = {
  --     "rpg":    "tag:rpg AND (title:ringforge OR text:ringforge)",
  --     "ringforge-mechanics": {
  --       "parent": "ringforge",
  --       "filter": "tag:mechanics"
  --     }
  --     clinic = 'tag:medicine AND tag:protocol AND NOT tag:draft',
  --   }
  projects = {},

  sidebar_width = 30,

  -- The one sidebar follows focus: nav when a markdown file is focused, views
  -- when no window holds a file. Set false to pin it to whatever you last chose
  -- (also toggleable at runtime with :PKMPanel autoswitch).
  sidebar_autoswitch = true,

  user = {
    name  = "",
    email = "",
  },

  -- Markdown Symbols
  symbols = {
    { trigger = '^-', key = '', expansion = '—' },
    { trigger = '^$',   key = '', expansion = '§' },
    { trigger = '^o',   key = '', expansion = 'º' },
    { trigger = '^a',   key = '', expansion = 'ª' },
  },

  -- PKM Mode and Explorer UI
  pkm_mode = {
    triggers = {
      open_note = true,   -- activate when any PKM note is opened (BufReadPost)
      enter_dir = false,  -- activate when CWD is/becomes PKM root (DirChanged)
    },
    layout = {
      sidebar  = false,    -- open views sidebar on activation
      bufpanel = true,    -- open buffer panel on activation
    },
    index = {
      prebuild = true,    -- eagerly rebuild index on activation if not yet built
    },
    syntax = {
      enabled = true,     -- enable PKM syntax highlighting on activation
      -- Highlight *all* markdown files, not only PKM notes. When true, a plain
      -- markdown buffer outside the vault gets the pure highlighting (list
      -- markers, citations, meta-comments, YAML injection) but NOT the note
      -- behaviour (frontmatter fold, window options). Off by default so opening
      -- an unrelated README is untouched. (This is the seam for extracting the
      -- highlighter as a standalone plugin.)
      highlight_all_markdown = false,
    },
  },

  display_mode = 'title',   -- 'filename' | 'title'; default label in panels and sidebar

  -- Trash
  trash = {
    enabled      = true,   -- soft-delete via .pkm-trash/
    max_age_days = 60,     -- auto-purge entries older than N days; 0 to disable
  },

  -- The default keymaps follow three mnemonic axes (v1.60.0 reorg). CONTENT
  -- prefixes say *what* — `<leader>n` notes, `<leader>c` citations/links,
  -- `<leader>f` find/search, `<leader>v` views, `<leader>M` markdown structure.
  -- SURFACE is `<leader>p` — the PERSISTENT panels you toggle and live with
  -- (sidebar, buffer bar; one key is both on and off). Transient pickers (browse,
  -- tags, the cyclable pop-up) are content and live under their verb (`<leader>f`),
  -- not here. WINDOW keys stay the user's own `<C-*>` scheme; pkm adds only
  -- `<C-Tab>` to cycle among open panes. Every entry is a config
  -- key (the stable contract) mapped to its lhs; set any to `false` to disable.
  -- `:help pkm-keymaps` is the reference; `:nmap <leader>` (every bind carries a
  -- `PKM: …` description) or which-key shows what is actually mapped now.
  keymaps = {
    -- Notes — the note lifecycle (`<leader>n`)
    new_note         = "<leader>nn",
    new_relative     = false,          -- note inheriting current tags (e.g. <leader>nN)
    new_journal      = "<leader>nj",
    new_scratchpad   = "<leader>ns",
    rename_note      = "<leader>nr",
    delete_note      = "<leader>nd",
    import_note      = "<leader>ni",
    convert_note     = "<leader>nx",
    promote_note     = "<leader>np",
    transpose_note   = "<leader>nT",
    change_note_type = "<leader>nC",
    set_title        = false,          -- buffer-only title (e.g. <leader>nt)
    -- Citations and links (`<leader>c`)
    insert_citation  = "<leader>cc",
    goto_citation    = "<leader>cg",
    link_note        = "<leader>cl",
    backlinks        = "<leader>cb",
    follow_link      = "gf",           -- natural, non-leader; overrides goto-file
    -- Tags on the current note (buffer-only; opt-in — bind to any free key)
    add_tag          = false,
    remove_tag       = false,
    -- Find / search — transient pickers (`<leader>f`)
    browse          = "<leader>ff",
    browse_tags     = "<leader>ft",
    nav_search      = "<leader>fp",    -- cyclable pop-up (nav; <C-l> → views → browse)
    -- Views — saved filters only, no panes (`<leader>v`)
    view_last    = "<leader>vl",
    view_list    = "<leader>va",       -- va = view all
    -- Panes — the PERSISTENT surfaces you toggle and live with (`<leader>p`)
    view_sidebar = "<leader>ps",       -- sidebar (views), also :PKMView sidebar
    view_buffers = "<leader>pb",       -- bottom buffer-list panel
    nav_panel    = false,              -- sidebar switched to the nav provider (e.g. <leader>pn)
    explorer     = false,              -- sidebar + buffer panel as a unit (e.g. <leader>pe)
    toggle_mode  = false,              -- :PKMPanel mode (e.g. <leader>pm)
    focus_sidebar = "<leader>P",       -- jump focus into/out of the sidebar
    view_panel   = false,              -- sidebar-buffer-local key to pop out into the views panel
    cycle_panes      = "<C-Tab>",      -- cycle focus among open panes (+ main window)
    cycle_panes_back = "<C-S-Tab>",    -- cycle focus backwards
    toggle_file_explorer = false,      -- superseded by view_sidebar + T (filename/title toggle)
    -- Markdown editing
    ---- Headers ----
    next_header        = "<leader>Mh",   -- :PKMHeader append (writes; not a motion)
    header_level_up    = "<leader>M^",
    header_level_down  = "<leader>M_",
    -- Header navigation: buffer-local on markdown, normal and visual mode,
    -- count-aware. Only same-level gets keys — Neovim's own ]] / [[ already
    -- jump header to header, and a key that repeats the editor is a key spent
    -- for nothing. Same-level motion has no native equivalent, so it takes
    -- ]h / [h: unmodified, and in the bracket family the native motion lives in.
    header_next_same   = "]h",   -- next header of the current header's level
    header_prev_same   = "[h",   -- previous header of the current header's level
    -- Any-level jumps, left unbound: this is ]] / [[ . Assign only if you want
    -- what those lack — a count, Visual mode, a jumplist entry, and working
    -- without the tree-sitter markdown parser (:PKMHeader next has all of it).
    header_next        = false,
    header_prev        = false,
    renumber_list      = "<leader>Mr",
    convert_list = false,   -- :PKMList convert (range or paragraph at cursor)
    toggle_syntax = false,  -- :PKMSyntax toggle (highlighting on/off, current buffer)
  },
}

-- =============================================================================
-- SECTION: Resolution
-- =============================================================================
--- Merge user config with defaults, resolve paths, validate, inject author.
---@param user_config table|nil
---@return table Resolved configuration
function M.resolve(user_config)
  local cfg = vim.tbl_deep_extend("force", defaults, user_config or {})

  -- Path resolution
  if not cfg.root_path then
    cfg.root_path = vim.fn.expand('~/Notes')
  end

  cfg.root_path = utils.normalize(vim.fn.expand(cfg.root_path))

  -- A trailing separator is a natural way to write a directory and it makes
  -- every path built from the root `root//folder`. Nothing errors — the OS
  -- opens it — but every comparison against a real note path is then off by one
  -- character, which is how a path stops matching itself.
  cfg.root_path = (cfg.root_path:gsub('[/\\]+$', ''))
  if cfg.root_path == '' then cfg.root_path = utils.sep end

  -- Only normalised when it was given. It is deliberately not derived here:
  -- for a root that is nobody's sibling the derived answer would be its parent
  -- directory, and recording that in the config would state as a fact what is
  -- only a guess. pkm.vault guesses it at call time instead, where an absent
  -- registry is a supported answer rather than a broken path.
  if cfg.vaults_path then
    cfg.vaults_path = utils.normalize(vim.fn.expand(cfg.vaults_path))
  end

  -- Validation. Silent whenever the root is the registry's to supply — a named
  -- vault, $PKM_VAULT, or merely a vaults_path, which on a first run is the
  -- whole configuration. root_path is then a placeholder nobody chose, and
  -- complaining about it buries the message that matters: pkm.vault says what
  -- is actually missing, and how to fix it.
  if vim.fn.isdirectory(cfg.root_path) == 0
  and not cfg.vault and not cfg.vaults_path and not vim.env.PKM_VAULT then
    vim.notify("PKM Critical: Root path does not exist: " .. cfg.root_path, vim.log.levels.ERROR)
  end

  -- Inject author into templates that carry an author field
  if cfg.user and cfg.user.name ~= "" then
    cfg.frontmatter_templates.note.author = cfg.user.name
    cfg.frontmatter_templates.agg.author = cfg.user.name
    cfg.frontmatter_templates.journal.author = cfg.user.name
  end

  return cfg
end

return M
