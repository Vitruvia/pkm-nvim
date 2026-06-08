# PKM.nvim

A personal knowledge management plugin for Neovim. Plain markdown notes with YAML frontmatter, bidirectional citations, a boolean filter system, and named project views. Local-first, cross-platform (Windows, WSL, Linux, macOS).

## Requirements

- Neovim ≥ 0.10
- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) *(optional — fallback UI provided for all pickers)*

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

~~~lua
{
  'Vitruvia/pkm-nvim',
  config = function()
    require('pkm').setup({
      root_path = vim.fn.expand('~/Notes'),
    })
  end,
}
~~~

## Note Types

Notes live in three folders with a clear promotion path:

| Folder | Purpose | Naming |
|---|---|---|
| Scratchpad | Quick capture, no friction | `YYYY-MM-DD_HH-MM-SS_scratch.md` |
| Journal | Timestamped entries | `YYYY-MM-DD_HH-MM-SS_journal.md` |
| Consolidated | Permanent numbered knowledge base | `0042_note_Title.md` |

Consolidated subtypes: `note`, `bib` (bibliography), `agg` (aggregate/collection).

## Commands

### Notes

| Command | Description |
|---|---|
| `:PKMNewNote` | Create a consolidated note |
| `:PKMNewJournal` | Create a journal entry |
| `:PKMNewScratchpad` | Create a scratchpad note |
| `:PKMRenameNote` | Rename current note with citation propagation |
| `:PKMDeleteNote` | Delete current note and remove all citations |
| `:PKMPromote` | Promote scratchpad to consolidated or journal |
| `:PKMConvertNote` | Normalize current note to its folder's format |
| `:PKMImport` | Import an external file into the PKM structure |

### Browse and Search

| Command | Description |
|---|---|
| `:PKMBrowse [expr]` | Browse notes with optional filter expression |
| `:PKMTags` | Browse notes by tag |
| `:PKMSearch` | Full-text search via ripgrep (requires `rg`) |

Filter examples: `tag:math AND title:fourier`, `tag:physics OR tag:math`, `filename:0042`, `NOT tag:draft`.

### Citations

| Command | Description |
|---|---|
| `:PKMInsertCitation` | Insert a citation at the cursor |
| `:PKMGotoCitation` | Jump to the note under the cursor |
| `:PKMUpdateReferences` | Rebuild citation frontmatter for the current buffer |

Inserting a citation automatically updates `cites` in the current note and `cited_by` in the cited note. The picker scores notes by active view and shared tags, prefixing contextually relevant results with `~`. In Telescope, `<C-v>` toggles a view-only mode.

### Views

Views are named filter expressions stored in `views.json` at your notes root. They support parent-child hierarchy: a subproject's effective filter is its own filter AND-ed with all ancestors.

| Command | Description |
|---|---|
| `:PKMViews` | Browse all views in a tree picker |
| `:PKMView [name]` | Open a named view |
| `:PKMViewNew` | Create or update a view |
| `:PKMViewNewSub` | Create a subproject view under a parent |
| `:PKMViewLast` | Reopen the last activated view |
| `:PKMViewSidebar [name]` | Toggle the persistent sidebar |
| `:PKMViewEdit` | Open `views.json` directly |
| `:PKMViewDelete [name]` | Remove a view |
| `:PKMExportView [name]` | Export a named view's notes to a folder |

**Sidebar keymaps:** `<CR>` enter view or open note · `b` / `<C-b>` back to views overview · `/` scoped search within current view · `r` refresh · `q` close.

### Export

| Command | Description |
|---|---|
| `:PKMExport` | Interactive: filter form → picker → destination |
| `:PKMExportView [name]` | Export a named view directly (no filter form) |

### Utilities

| Command | Description |
|---|---|
| `:PKMBuffers` | Toggle a persistent bottom panel listing open buffers |
| `:PKMStats` | Show note counts per folder |
| `:PKMMergeTags` | Merge one or more tags into a target tag |

## Configuration

~~~lua
require('pkm').setup({
  root_path = vim.fn.expand('~/Notes'),  -- required

  folders = {
    scratchpad   = '01-Scratchpad',
    journal      = '02-Journal',
    consolidated = '03-Consolidated',
    templates    = 'templates',
  },

  sync = {
    enabled           = true,
    auto_sync_on_save = true,
  },

  sidebar_width = 40,

  -- Symbol abbreviations and insert-mode keymaps, registered per buffer
  symbols = {
    { trigger = 'emdash', key = '<M-->', expansion = '—' },
  },

  keymaps = {
    new_note        = '<leader>nn',
    new_journal     = '<leader>nj',
    new_scratchpad  = '<leader>ns',
    rename_note     = '<leader>nr',
    delete_note     = '<leader>nd',
    insert_citation = '<leader>nc',
    goto_citation   = '<leader>ng',
    search          = '<leader>nf',
    browse_tags     = '<leader>nt',
    view_last       = '<leader>nV',
    view_sidebar    = '<leader>nS',
    -- see :help pkm-keymaps for the full list
  },
})
~~~

## Views Quick Start

~~~
:PKMViewNew
" Name: physics
" Filter: tag:physics AND NOT tag:draft

:PKMView physics

:PKMViewNewSub
" Name: physics-problems
" Parent: physics
" Filter: tag:problem

:PKMViewSidebar physics
~~~

Views are stored in `views.json` alongside your notes and can be version-controlled with them.

## Help

~~~
:help pkm
:help pkm-commands
:help pkm-views
:help pkm-citations
:help pkm-export
~~~
