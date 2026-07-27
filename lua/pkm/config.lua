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
  -- Optional: left unset it is taken to be root_path's parent, which is the
  -- shape the vaults have on disk. A root with no registry beside it keeps
  -- working exactly as it always has.
  vaults_path = nil,

  -- Active vault, by name, resolved through the registry into root_path at
  -- startup. Overridden for one session by $PKM_VAULT, which is how the normal
  -- configuration can be pointed at the test vault without being edited.
  -- Setting this instead of root_path is what stops the active vault being a
  -- hardcoded path that every rename has to chase.
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
    },
  },

  display_mode = 'title',   -- 'filename' | 'title'; default label in panels and sidebar

  -- Trash
  trash = {
    enabled      = true,   -- soft-delete via .pkm-trash/
    max_age_days = 60,     -- auto-purge entries older than N days; 0 to disable
  },

  keymaps = {
    -- Note operations
    new_note         = "<leader>nn",
    new_relative     = false,   -- new note inheriting the current note's tags
    new_journal      = "<leader>nj",
    new_scratchpad   = "<leader>ns",
    rename_note      = "<leader>nr",
    insert_citation  = "<leader>nc",
    goto_citation    = "<leader>ng",
    delete_note      = "<leader>nd",
    link_note        = "<leader>nl",
    follow_link      = "gf",
    backlinks        = "<leader>nb",
    import_note      = "<leader>ni",
    convert_note     = "<leader>nx",
    promote_note     = "<leader>np",
    transpose_note   = "<leader>nT",
    change_note_type = "<leader>nC",
    set_title        = false,
    add_tag          = false,
    remove_tag       = false,
    -- Navigation
    view_last    = "<leader>vl",
    view_list    = "<leader>va", -- va = view all
    view_sidebar = "<leader>vs",
    view_panel   = false,   -- sidebar-buffer-local key to pop out into the views panel
    view_buffers = "<leader>vb",
    toggle_file_explorer = false,   -- superseded by view_sidebar + T (filename/title toggle)
    focus_sidebar = "<leader>s",   -- jump focus directly to sidebar window
    -- PKMMode
    toggle_mode   = false,   -- :PKMMode toggle
    -- Search and browsing
    browse          = "<leader>nf",
    browse_tags     = "<leader>nt",
    -- Markdown editing
    ---- Headers ----
    next_header        = "<leader>Mh",   -- :PKMHeaderAppend (writes; not a motion)
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
    -- without the tree-sitter markdown parser (:PKMHeaderNext has all of it).
    header_next        = false,
    header_prev        = false,
    renumber_list      = "<leader>Mr",
    convert_list = false,   -- :PKMConvertList (range or paragraph at cursor)
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

  -- Only normalised when it was given. It is deliberately not derived here:
  -- for a root that is nobody's sibling the derived answer would be its parent
  -- directory, and recording that in the config would state as a fact what is
  -- only a guess. pkm.vault guesses it at call time instead, where an absent
  -- registry is a supported answer rather than a broken path.
  if cfg.vaults_path then
    cfg.vaults_path = utils.normalize(vim.fn.expand(cfg.vaults_path))
  end

  -- Validation. Silent when a vault was named: root_path is then a placeholder
  -- about to be replaced by the registry, and complaining about a path nobody
  -- chose would bury the message that matters — which pkm.vault emits if the
  -- named vault turns out not to be registered.
  if vim.fn.isdirectory(cfg.root_path) == 0 and not cfg.vault and not vim.env.PKM_VAULT then
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
