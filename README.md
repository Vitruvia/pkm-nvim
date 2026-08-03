# PKM.nvim

A personal knowledge management plugin for Neovim. Plain markdown notes with YAML frontmatter, bidirectional citations, a boolean filter system, and named project views. Local-first, cross-platform (Windows, WSL, Linux, macOS).

## Requirements

- Neovim ≥ 0.10
- [pkm-syntax](https://github.com/Vitruvia/pkm-syntax) — the markdown highlighting, extracted into its own plugin (see Installation). Without it pkm-nvim still loads, just without highlighting.
- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) *(optional — fallback UI provided for all pickers)*

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

~~~lua
{
  'Vitruvia/pkm-nvim',
  dependencies = { 'Vitruvia/pkm-syntax' },   -- markdown highlighting (required)
  config = function()
    require('pkm').setup({
      root_path = vim.fn.expand('~/Notes'),
    })
  end,
}
~~~

`pkm-syntax` also stands alone: `require('pkm-syntax').setup()` highlights **every**
markdown buffer, independent of pkm-nvim.

## Note Types

Notes live in three folders with a clear promotion path:

| Folder | Purpose | Naming |
|---|---|---|
| Scratchpad | Quick capture, no friction | `YYYY-MM-DD_HH-MM-SS_scratch.md` |
| Journal | Timestamped entries | `YYYY-MM-DD_HH-MM-SS_journal.md` |
| Consolidated | Permanent numbered knowledge base | `0042_note_Title.md` |

Consolidated subtypes: `note`, `bib` (bibliography), `agg` (aggregate/collection).

## Commands

Every command is a **verb-context**: `:PKM<Context> <verb> [args]`. Type
`:PKM<Tab>` for the ~15 contexts, and `:PKMNote <Tab>` (etc.) for a context's
verbs. A context with a friendly default does the common thing bare — `:PKMNote`
creates, `:PKMCite <target>` cites, `:PKMBrowse <expr>` browses.

### Notes — `:PKMNote <verb>`

| Command | Description |
|---|---|
| `:PKMNote [new] [note\|agg\|bib]` | Create a note (bare prompts; `title=` and `by=<agent>` optional) |
| `:PKMNote journal` | Create a journal entry |
| `:PKMNote scratch` | Create a scratchpad note |
| `:PKMNote relative [type]` | Create a note inheriting the current note's tags |
| `:PKMNote rename [name]` | Rename current note (citations propagate) |
| `:PKMNote delete` | Delete current note (moves to trash) |
| `:PKMNote promote` | Promote scratchpad to consolidated note or journal |
| `:PKMNote convert` | Convert current note to a different type |
| `:PKMNote changetype` | Change a consolidated note's type (`note`/`agg`/`bib`) |
| `:PKMNote transpose` | Move note to a different PKM folder and convert it |
| `:PKMNote import` | Import the current file into the PKM system |
| `:PKMNote settitle [text]` | Set the title frontmatter field (buffer only) |

### Tags — `:PKMTag` (one note) · `:PKMTags` (all notes)

| Command | Description |
|---|---|
| `:PKMTag add <tag> [note=<ref>]` | Add a tag to the current note (or to `note=<ref>` on disk) |
| `:PKMTag remove <tag> [note=<ref>]` | Remove a tag |
| `:PKMTag merge` | Merge one or more tags into a target tag |
| `:PKMTags add\|remove\|rename <tag>` | The same across **all** notes, with a change-list confirm |

### Citations and Links — `:PKMCite <verb>`

| Command | Description |
|---|---|
| `:PKMCite [add] <target>` | Cite a note from the current one (bare = picker) |
| `:PKMCite remove [target]` | Remove a citation (bare = picker over what this note cites) |
| `:PKMCite insert` | Insert a citation at the cursor |
| `:PKMCite goto` | Jump to the note under the cursor |
| `:PKMCite update` | Rebuild citation frontmatter for the current buffer |
| `:PKMCite link` | Insert a link to another note |
| `:PKMCite follow` | Follow the link/citation under the cursor |
| `:PKMCite backlinks` | Show notes that cite the current one |

Inserting a citation automatically updates `cites` in the current note and `cited_by` in the cited note. The picker scores notes by active view and shared tags, prefixing contextually relevant results with `~`. In Telescope, `<C-v>` toggles a view-only mode.

### Browse and Search — `:PKMBrowse <verb>`

| Command | Description |
|---|---|
| `:PKMBrowse [expr]` | Browse notes with an optional filter expression |
| `:PKMBrowse tags` | Browse notes by tag |
| `:PKMBrowse recent [n]` | Browse recently modified notes |
| `:PKMBrowse orphans` | Show notes with no tags, no citations, and no matching view |

Filter examples: `tag:math AND title:fourier`, `tag:physics OR tag:math`, `filename:0042`, `NOT tag:draft`.

### Views

Views are named filter expressions stored in `views.json` at your notes root. They support parent-child hierarchy: a subproject's effective filter is its own filter AND-ed with all ancestors.

| Command | Description |
|---|---|
| `:PKMView [name]` | Open a named view |
| `:PKMView list` | Browse all views in a tree picker |
| `:PKMView add\|remove <view> [note=<ref>]` | Add/remove a note to/from a view |
| `:PKMView new` | Create a view — prompts for a simple view or a subproject |
| `:PKMView update [name]` | Edit or reparent a view |
| `:PKMView rename <old> <new>` | Rename a view |
| `:PKMView last` | Reopen the last activated view |
| `:PKMView sidebar [name]` | Toggle the persistent sidebar |
| `:PKMView edit` | Open `views.json` directly |
| `:PKMView delete [name]` | Remove a view |
| `:PKMView export [name]` | Export a named view's notes to a folder |

**Sidebar keymaps:** `<CR>` enter view or open note · `b` / `<C-b>` back to views overview · `/` scoped search within current view · `r` refresh · `q` close.

### Export — `:PKMExport`

| Command | Description |
|---|---|
| `:PKMExport [simple\|deep]` | Interactive export (bare opens the mode menu) |
| `:PKMView export [name]` | Export a named view directly (no filter form) |

### Markdown Editing — `:PKMHeader` · `:PKMList`

| Command | Description |
|---|---|
| `:PKMHeader append` | Duplicate current header with its counter incremented, append at EOF |
| `:PKMHeader next\|prev [same\|h1-h6] [count]` | Jump to next/prev header — any level, or the level given; a bare number is the count |
| `:PKMHeader levelup` / `:PKMHeader leveldown` | Shift header level in range (default: whole buffer) |
| `:PKMList renumber` | Renumber an ordered sequence in range or current paragraph |
| `:PKMList convert [to_ordered\|to_unordered]` | Convert list style in range or current paragraph |
| `:PKMList wrap` | Structure-aware reflow to `textwidth` (range or current paragraph) |

The header-motion **keymaps** (`]h` / `[h` by default) still take a Vim count
(`3]h`); on the command, the count is an argument (`:PKMHeader next 3`).

`:PKMList` understands the **legal (LC 95/1998) marker hierarchy** — artigo
`Art. Nº`, parágrafo `§ Nº`, inciso `I -`, alínea `a)`, subalínea `i.` — for both
renumber and highlight, alongside ordinary digit/bullet lists. `:PKMList wrap`
(also `gq`/`gqq`/`gq{motion}` on a note) keeps list continuations at a 4-column
indent and reflows blockquotes with a repeated `>` prefix. See `doc/CONVENTIONS.md`
§ Lists for the full marker table and wrap rules.

### Panels, Trash and Utilities — `:PKMPanel` · `:PKMTrash`

| Command | Description |
|---|---|
| `:PKMPanel [explorer]` | Toggle the explorer (sidebar + buffer panel) |
| `:PKMPanel buffers` | Toggle a persistent bottom panel listing open buffers |
| `:PKMPanel nav` | Toggle the current-file navigation panel (heading index; `<CR>` jumps, `/` filters) |
| `:PKMPanel sidebar [name]` | Toggle the view sidebar |
| `:PKMPanel mode [on\|off]` | Toggle PKM mode (explorer + index + syntax) |
| `:PKMTrash restore` | Browse and restore notes from the trash |
| `:PKMTrash empty` | Permanently delete all trashed notes |
| `:PKMSyntax [on\|off\|toggle]` | Toggle PKM markdown highlighting on the current buffer (bare = toggle) |
| `:PKMCheck` | Audit the vault (frontmatter, citation graph, numbering, vault refs) |
| `:PKMStats` | Show note statistics |
| `:PKMToggleAutoSync` | Toggle automatic reference synchronization |

### Vaults

A vault is a folder with its own numbering, citation graph and views; vaults
never communicate. Most people need exactly one and can ignore this section —
`root_path` on its own behaves as it always has. The registry exists so the
active vault is a *name* rather than a path: see **Configuration** below.

| Command | Description |
|---|---|
| `:PKMVault[!] [name]` | Switch the active vault (no argument lists them; `!` also makes it the default) |
| `:PKMVault[!] new <name>` | Create a vault: folder, skeleton and registry entry (`!` for no git repository) |
| `:PKMVault rename <from> <to>` | Rename a vault, keeping its number |
| `:PKMVault renumber <name> <n>` | Renumber a vault, keeping its name |
| `:PKMVault unregister [name]` | Move a vault out of the registry into `Unregistered/` (always confirms) |
| `:PKMVault adopt [folder]` | Register a folder as a vault, contents untouched |

Renaming and renumbering move the folder and touch no note. Unregistering moves
the folder intact — **no command here deletes a note**; `:PKMVault adopt` is the
way back. Both refuse while a buffer under the vault has unsaved changes.

With more than one vault registered, the buffer panel prefixes each note with
its vault (`V01`) and names the active one in its header, and the views sidebar
carries it in its title. For a statusline, `require('pkm.vault').statusline`
returns `V01 Vitruvia` — and appends `[buf V02]` when the buffer in front of you
belongs to a different vault, which is the one state where the screen and the
truth disagree: that buffer is outside the root, so saving it no longer stamps
its timestamp, syncs its citations or touches the index.

~~~lua
require('lualine').setup({
  sections = { lualine_x = { require('pkm.vault').statusline } },
})
~~~

## Configuration

~~~lua
require('pkm').setup({
  -- One of two shapes. Either name the folder directly:
  root_path = vim.fn.expand('~/Notes'),

  -- or, with more than one vault, name only the directory they sit in:
  --
  --   vaults_path = vim.fn.expand('~/Note-Vault'),   -- holds vaults.json
  --
  -- That is the whole configuration. Which vault opens is the registry's own
  -- default, set with `:PKMVault! <name>` — it lives there rather than here
  -- because the registry is what performs a rename and can correct itself,
  -- while a name written in this file cannot: a rename never reads it.
  --
  -- Two optional overrides, most specific first: $PKM_VAULT for one session,
  -- and `vault = 'Personal'` for one machine or profile.
  --
  -- On the very first run the registry does not exist yet: `:PKMVault adopt`
  -- registers the folders that are already there, without moving them, and the
  -- first one registered becomes the default.

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
:PKMView new
" View type: Simple view
" Name: physics
" Filter: tag:physics AND NOT tag:draft

:PKMView physics

:PKMView new
" View type: Subproject
" Name: physics-problems
" Parent: physics
" Filter: tag:problem

:PKMView sidebar physics
~~~

Views are stored in `views.json` alongside your notes and can be version-controlled with them.

## For assistants — `pkm.api`

PKM.nvim exposes a stable Lua API so an LLM coding assistant drives the vault
through the plugin's own cores instead of hand-editing files (which desyncs the
citation graph, numbering, and index). `require('pkm.api')` covers reads
(retrieval, backlinks, views) and the note lifecycle — create, body writing
(`set_body`/`append_body`/`insert_section`), `rename`/`changetype`/`transpose`,
tag and membership writes, `annotate`, and more.

- **`doc/PKM_API.md`** — the API reference (functions, arguments, return shapes).
- **`doc/AGENT_PROTOCOL.md`** — the doctrine: how an assistant is expected to
  behave in a vault (authorship marker, citation discipline, memory organisation).
- **`doc/CONVENTIONS.md`** — note formats, in-text citations, and the list marker
  conventions the renumber/highlight/wrap recognise.
- **`:PKMAgentProtocol install`** — installs the bundled **`pkm-notes`** skill and
  the **`/pkm-learning`** slash command into your assistant's config, so the
  protocol travels with the tooling. `update` refreshes it; `path` reports where.

## Help

~~~
:help pkm.txt
:help pkm-commands
:help pkm-sidebar
:help pkm-citations
:help pkm-export
~~~
