# PKM.nvim

A personal knowledge management plugin for Neovim. Plain text, structured, bidirectional — built to stay out of your way.

> **Status:** Functional and in daily use. API is stable; some features are still being added.

---

## What It Does

PKM.nvim manages a collection of markdown notes organized around a three-stage workflow:

| Stage | Folder | Purpose |
|---|---|---|
| **Scratchpad** | `01-Scratchpad/` | Quick capture, fleeting ideas, no friction |
| **Journal** | `02-Journal/` | Timestamped daily entries, personal log |
| **Consolidated** | `03-Consolidated/` | Permanent numbered knowledge base |

Notes in the consolidated folder are typed: regular notes (`note`), bibliography entries (`bib`), and collections (`agg`). All notes carry YAML frontmatter that is kept in sync automatically.

The centerpiece is a **bidirectional citation system**: when you cite a note, the cited note automatically records the backlink. Deleting a note cleans up all references to it.

---

## Features

- **Bidirectional citations** — insert a citation in one note, backlink appears in the other automatically
- **Structured frontmatter** — YAML metadata per note type, kept in sync with filenames
- **Note lifecycle** — create scratchpads, promote to journal or consolidated, convert between types
- **Flexible timestamps** — full datetime, date+time, date-only, or unknown
- **Telescope integration** — fuzzy note search, tag browser, citation picker (optional but recommended)
- **Export utility** — filter notes by tag, title, or body text; copy matched files to a folder
- **Citation cleanup** — safely delete notes and remove all stale references
- **Cross-platform** — Windows, WSL, Linux, macOS

---

## Requirements

- Neovim ≥ 0.10
- [`nvim-telescope/telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim) — optional but strongly recommended
- [`BurntSushi/ripgrep`](https://github.com/BurntSushi/ripgrep) — required if using Telescope search

---

## Installation

### lazy.nvim

```lua
{
  'yourusername/pkm.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim',  -- optional
  },
  config = function()
    require('pkm').setup({
      root_path = vim.fn.expand('~/Notes'),
      user = { name = "Your Name" },
    })
  end,
}
```

### packer

```lua
use {
  'yourusername/pkm.nvim',
  requires = { 'nvim-telescope/telescope.nvim' },
  config = function()
    require('pkm').setup({ root_path = vim.fn.expand('~/Notes') })
  end,
}
```

---

## Quick Start

```lua
require('pkm').setup({
  root_path = vim.fn.expand('~/Notes'),

  user = {
    name = "Your Name",
  },

  keymaps = {
    new_note       = "<leader>nn",
    new_journal    = "<leader>nj",
    new_scratchpad = "<leader>ns",
    quick_capture  = "<leader>nq",
    insert_citation = "<leader>nc",
    search         = "<leader>nf",
    browse_tags    = "<leader>nt",
  },
})
```

PKM will create the folder structure under `root_path` on first use.

---

## Commands

### Note Creation

| Command | Description |
|---|---|
| `:PKMNewNote [type]` | Create a consolidated note. Type: `note`, `bib`, `agg`. Prompts if omitted. |
| `:PKMNewJournal` | Create a journal entry timestamped to now |
| `:PKMNewScratchpad` | Create a new scratchpad |
| `:PKMQuickCapture` | Open today's scratchpad (create if absent) and append a timestamp header |
| `:PKMImport` | Import the current file into the PKM structure |

### Note Management

| Command | Description |
|---|---|
| `:PKMConvertNote` | Normalize the current note to match its folder's format |
| `:PKMPromote` | Promote a scratchpad to a consolidated note or journal entry |
| `:PKMDeleteNote` | Delete the current note and clean up all references to it |

### Navigation

| Command | Description |
|---|---|
| `:PKMFollowLink` | Open the note referenced by the `[[wiki-link]]` under the cursor |
| `:PKMLinkNote` | Insert a `[[wiki-link]]` to another note |
| `:PKMBacklinks` | Show all notes that link to the current note |
| `:PKMGotoCitation` | Jump to the note referenced by the citation under the cursor |

### Search & Browse

| Command | Description |
|---|---|
| `:PKMSearch` | Fuzzy search note contents (Telescope + ripgrep) |
| `:PKMFind` | Find notes by filename (Telescope) |
| `:PKMTags` | Browse notes by tag (Telescope) |
| `:PKMStats` | Show a statistics window |

### Citations

| Command | Description |
|---|---|
| `:PKMInsertCitation` | Pick a note and insert a structured citation |
| `:PKMUpdateReferences` | Scan the current file and rebuild its `cites` frontmatter list |
| `:PKMSync` | Force a full reference sync and cleanup across all notes |

### Export

| Command | Description |
|---|---|
| `:PKMExport` | Filter notes by tag/title/body text and copy matches to a folder |

### Sync

| Command | Description |
|---|---|
| `:PKMToggleAutoSync` | Toggle automatic reference sync on save |

---

## Note Frontmatter

Each note type carries a standard frontmatter template. Example for a consolidated note:

```yaml
---
title: "Introduction to Fourier Analysis"
author: "Your Name"
created_on: "2024-03-15_09-30-00"
last_updated_on: "2024-03-15_14-22-11"
tags:
  - mathematics
  - analysis
cites:
  notes:
    - identifier: note-0017
      title: "Real Analysis Foundations"
      link: "[[0017_note_Real_Analysis_Foundations]]"
  bib:
    - identifier: bib-0003
      title: "Fourier Analysis — Stein & Shakarchi"
      link: "[[0003_bib_Fourier_Analysis_Stein_Shakarchi]]"
cited_by:
  notes: []
  bib: []
---
```

The `cites` and `cited_by` fields are maintained automatically. Manual edits are safe but will be normalized on the next sync.

---

## File Naming

Consolidated notes follow the pattern `NNNN_type_Title_Words.md`:

```
0042_note_Introduction_to_Fourier_Analysis.md
0003_bib_Fourier_Analysis_Stein_Shakarchi.md
0007_agg_Real_Analysis_Reading_List.md
```

Journal entries and scratchpads use timestamps:

```
journal_2024-03-15_09-30-00.md
scratch_2024-03-15_14-00-00.md
```

---

## Export

`:PKMExport` opens a filter form:

```
╭─ PKMExport: Advanced Filter ──────────────────────────────────────╮
│  Tags ANY  (OR) :  mathematics, physics                           │
│  Tags ALL (AND) :  proof                                          │
│  Title contains :                                                 │
│  Text  contains :  Fourier                                        │
╰───────────────────────────────────────────────────────────────────╯
```

After pressing `<CR>`, matched notes appear in a Telescope picker for review and individual selection. Confirmed files are copied to a destination folder you specify.

Useful for preparing a set of notes to share with an LLM, export for review, or archive.

---

## Configuration Reference

```lua
require('pkm').setup({
  root_path = nil,  -- required; auto-detects home dir if omitted

  folders = {
    scratchpad   = "01-Scratchpad",
    journal      = "02-Journal",
    consolidated = "03-Consolidated",
    templates    = "templates",
  },

  sync = {
    enabled           = true,
    auto_sync_on_save = true,
  },

  timestamp = {
    default_format = "full",  -- "full" | "date_time" | "date_only"
    auto_timestamp = true,
  },

  user = {
    name        = "",
    email       = "",
    institution = "",
  },

  keymaps = {
    new_note        = "<leader>nn",
    new_journal     = "<leader>nj",
    new_scratchpad  = "<leader>ns",
    quick_capture   = "<leader>nq",
    convert_note    = "<leader>nx",
    promote_note    = "<leader>np",
    import_note     = "<leader>ni",
    delete_note     = "<leader>nd",
    insert_citation = "<leader>nc",
    goto_citation   = "<leader>ng",
    link_note       = "<leader>nl",
    follow_link     = "gf",
    backlinks       = "<leader>nb",
    search          = "<leader>nf",
    browse_tags     = "<leader>nt",
  },
})
```

---

## License

MIT — see [LICENSE](LICENSE).
