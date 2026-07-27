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

The most-used commands are grouped below. See `:help pkm-commands` for the
complete reference.

### Notes

| Command | Description |
|---|---|
| `:PKMNewNote` | Create a consolidated note |
| `:PKMNewJournal` | Create a journal entry |
| `:PKMNewScratchpad` | Create a scratchpad note |
| `:PKMRenameNote` | Rename current consolidated note (citations propagate) |
| `:PKMDeleteNote` | Delete current note (moves to trash) |
| `:PKMPromote` | Promote scratchpad to consolidated note or journal |
| `:PKMConvertNote` | Convert current note to a different type |
| `:PKMChangeType` | Change a consolidated note's type (`note`/`agg`/`bib`) |
| `:PKMTranspose` | Move note to a different PKM folder and convert it |
| `:PKMImport` | Import the current file into the PKM system |
| `:PKMSetTitle` | Set the title frontmatter field (buffer only) |

### Tags and Metadata

| Command | Description |
|---|---|
| `:PKMAddTag [tag]` | Append a tag (tag panel, or directly with an argument) |
| `:PKMRemoveTag [tag]` | Remove a tag (tag panel, or directly with an argument) |
| `:PKMMergeTags` | Merge one or more tags into a target tag |
| `:PKMUpdateReferences` | Rebuild citation frontmatter for the current buffer |
| `:PKMToggleAutoSync` | Toggle automatic reference synchronization |

### Citations and Links

| Command | Description |
|---|---|
| `:PKMInsertCitation` | Insert a citation at the cursor |
| `:PKMGotoCitation` | Jump to the note under the cursor |
| `:PKMLinkNote` | Insert a link to another note |
| `:PKMFollowLink` | Follow the link/citation under the cursor |
| `:PKMBacklinks` | Show notes that cite the current one |

Inserting a citation automatically updates `cites` in the current note and `cited_by` in the cited note. The picker scores notes by active view and shared tags, prefixing contextually relevant results with `~`. In Telescope, `<C-v>` toggles a view-only mode.

### Browse and Search

| Command | Description |
|---|---|
| `:PKMBrowse [expr]` | Browse notes with an optional filter expression |
| `:PKMTags` | Browse notes by tag |
| `:PKMBrowseRecent` | Browse recently modified notes |
| `:PKMOrphans` | Show notes with no tags, no citations, and no matching view |

Filter examples: `tag:math AND title:fourier`, `tag:physics OR tag:math`, `filename:0042`, `NOT tag:draft`.

### Views

Views are named filter expressions stored in `views.json` at your notes root. They support parent-child hierarchy: a subproject's effective filter is its own filter AND-ed with all ancestors.

| Command | Description |
|---|---|
| `:PKMViews` | Browse all views in a tree picker |
| `:PKMView [name]` | Open a named view |
| `:PKMViewNew` | Create a view — prompts for a simple view or a subproject |
| `:PKMViewUpdate [name]` | Edit, rename, or reparent a view |
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

### Markdown Editing

| Command | Description |
|---|---|
| `:PKMHeaderAppend` | Duplicate current header with its counter incremented, append at EOF |
| `:[count]PKMHeaderNext [same\|h1-h6]` | Jump to the next header — any level, or the level given (a bare number is the count) |
| `:[count]PKMHeaderPrev [same\|h1-h6]` | Same, backwards |
| `:PKMHeaderLevelUp` / `:PKMHeaderLevelDown` | Shift header level in range (default: whole buffer) |
| `:PKMRenumberList` | Renumber an ordered sequence in range or current paragraph |
| `:PKMConvertList` | Convert list style in range or current paragraph |

### Explorer, Trash and Utilities

| Command | Description |
|---|---|
| `:PKMExplorer` | Toggle the explorer (sidebar + buffer panel) |
| `:PKMMode` | Toggle PKM mode (explorer + index + syntax) |
| `:PKMBuffers` | Toggle a persistent bottom panel listing open buffers |
| `:PKMRestoreNote` | Browse and restore notes from the trash |
| `:PKMEmptyTrash` | Permanently delete all trashed notes |
| `:PKMStats` | Show note statistics |

### Vaults

A vault is a folder with its own numbering, citation graph and views; vaults
never communicate. Most people need exactly one and can ignore this section —
`root_path` on its own behaves as it always has. The registry exists so the
active vault is a *name* rather than a path: see **Configuration** below.

| Command | Description |
|---|---|
| `:PKMVault [name]` | Switch the active vault (no argument lists them, marking the active one) |
| `:PKMVaultNew[!] <name>` | Create a vault: folder, skeleton and registry entry (`!` for no git repository) |
| `:PKMVaultRename <from> <to>` | Rename a vault, keeping its number |
| `:PKMVaultRenumber <name> <n>` | Renumber a vault, keeping its name |
| `:PKMVaultUnregister [name]` | Move a vault out of the registry into `Unregistered/` (always confirms) |
| `:PKMVaultAdopt [folder]` | Register a folder as a vault, contents untouched |

Renaming and renumbering move the folder and touch no note. Unregistering moves
the folder intact — **no command here deletes a note**; `:PKMVaultAdopt` is the
way back. Both refuse while a buffer under the vault has unsaved changes.

## Configuration

~~~lua
require('pkm').setup({
  -- One of two shapes. Either name the folder directly:
  root_path = vim.fn.expand('~/Notes'),

  -- or, with more than one vault, name the directory they sit in and pick one
  -- by name. Nothing then records a path to any vault, so renaming or
  -- renumbering one never edits this file:
  --
  --   vaults_path = vim.fn.expand('~/Note-Vault'),   -- holds vaults.json
  --   vault       = 'Personal',                      -- resolved through it
  --
  -- $PKM_VAULT overrides `vault` for one session. On the very first run the
  -- registry does not exist yet: `:PKMVaultAdopt` registers the folders that
  -- are already there, without moving them.

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

  sidebar_width = 30,
  display_mode  = 'title',   -- 'title' | 'filename': default label in panels/sidebar

  -- Symbol expansions registered per PKM buffer (defaults shown).
  -- `key` is an optional insert-mode mapping; `expansion` is required.
  -- See :help pkm-configuration for the trigger scheme.
  symbols = {
    { trigger = '^-', key = '', expansion = '—' },
    { trigger = '^$', key = '', expansion = '§' },
  },

  keymaps = {
    new_note        = '<leader>nn',
    new_journal     = '<leader>nj',
    new_scratchpad  = '<leader>ns',
    rename_note     = '<leader>nr',
    delete_note     = '<leader>nd',
    insert_citation = '<leader>nc',
    goto_citation   = '<leader>ng',
    browse          = '<leader>nf',
    browse_tags     = '<leader>nt',
    view_last       = '<leader>vl',
    view_sidebar    = '<leader>vs',
    -- see :help pkm-keymaps for the full list
  },
})
~~~

## Views Quick Start

~~~
:PKMViewNew
" View type: Simple view
" Name: physics
" Filter: tag:physics AND NOT tag:draft

:PKMView physics

:PKMViewNew
" View type: Subproject
" Name: physics-problems
" Parent: physics
" Filter: tag:problem

:PKMViewSidebar physics
~~~

Views are stored in `views.json` alongside your notes and can be version-controlled with them.

## Help

~~~
:help pkm.txt
:help pkm-commands
:help pkm-sidebar
:help pkm-citations
:help pkm-export
~~~
