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

  projects = {
      ringforge = 'tag:ringforge AND tag:"role-playing game"',
    },
  -- Named project views. Each key is a view name; each value is a filter
  -- expression string. Activated with :PKMView <name>.
  -- Example:
  --   projects = {
  --     rpg    = 'tag:rpg AND (title:ringforge OR text:ringforge)',
  --     clinic = 'tag:medicine AND tag:protocol AND NOT tag:draft',
  --   }

  user = {
    name  = "",
    email = "",
  },

  keymaps = {
    new_note        = "<leader>nn",
    new_journal     = "<leader>nj",
    new_scratchpad  = "<leader>ns",
    search          = "<leader>nf",
    browse_tags     = "<leader>nt",
    insert_citation = "<leader>nc",
    goto_citation   = "<leader>ng",
    delete_note     = "<leader>nd",
    link_note       = "<leader>nl",
    follow_link     = "gf",
    backlinks       = "<leader>nb",
    quick_capture   = "<leader>nq",
    import_note     = "<leader>ni",
    convert_note    = "<leader>nx",
    promote_note    = "<leader>np",
    transpose_note  = "<leader>nT",
    change_note_type = "<leader>nC",
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

  -- Validation
  if vim.fn.isdirectory(cfg.root_path) == 0 then
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
