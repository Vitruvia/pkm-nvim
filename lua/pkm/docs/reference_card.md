# PKM System - Quick Reference Card

## Essential Commands (Daily Use)

### Note Creation
```vim
<leader>nn  :PKMNewNote          " New consolidated note
<leader>nj  :PKMNewJournal       " New journal entry
<leader>ns  :PKMNewScratchpad    " New scratchpad
<leader>nq  :PKMQuickCapture     " Quick capture (most used!)
<leader>nx  :PKMConvertNote      " Convert scratchpad→journal/note
```

### Citations
```vim
<leader>nc  :PKMInsertCitation   " Insert bib[N] or note[N]
<leader>ng  :PKMGotoCitation     " Jump to citation source
K           :PKMShowCitationPreview  " Preview (on citation)
            :PKMUpdateReferences " Update frontmatter refs
```

### Navigation
```vim
<leader>nl  :PKMLinkNote         " Link to another note
gf          :PKMFollowLink       " Follow link under cursor
<leader>nb  :PKMBacklinks        " Show who links here
```

### Search & Browse
```vim
<leader>nf  :PKMSearch [query]   " Search all notes
<leader>nt  :PKMBrowseTags       " Browse by tags
<leader>nr  :PKMRecentJournals   " Recent journals
```

### Utilities
```vim
            :PKMStats            " Statistics dashboard
            :PKMUpdateFrontmatter      " Edit YAML
            :PKMValidateFrontmatter    " Check YAML
```

## File Naming Patterns

### Consolidated Notes
```
0001_agg_Topic_Name.md      " Aggregate/collection
0002_note_Specific_Topic.md " Regular note
0003_bib_Book_Title.md      " Bibliography entry
```

### Journals
```
journal_2025-10-10_14-30-45.md  " Full timestamp
journal_2025-10-10_14-30.md     " Hour and minute
journal_2025-10-10.md           " Date only
journal_2025-10-10_99-99-99.md  " Unknown time (imports)
```

### Scratchpads
```
scratch_2025-10-10_14-30-45.md  " Any format
```

## Frontmatter Templates

### Consolidated Note
```yaml
---
title: "Note Title"
author: "Your Name"
date: 2025-10-10
tags:
  - tag1
  - tag2
status: draft        # draft | incubation | mature
references:
  - type: bib
    number: 7
    title: "Book Title"
    link: "[[0007_bib_Book_Title]]"
---
```

### Journal Entry
```yaml
---
date: 2025-10-10
time: 14-30-45      # or "unknown"
tags:
  - reflection
location: "Home"    # optional
---
```

### Bibliography
```yaml
---
title: "Book Title"
author: "Author Name"
date: 2025
source_type: book   # book | paper | article | video
source_location: "/path/to/file.pdf"
tags:
  - philosophy
---
```

## Citation Syntax

### In Text
```markdown
According to the research bib[7], we find that...
This aligns with note[12] which discusses...
Multiple citations bib[7] show note[12] similar patterns.
```

### In Frontmatter (auto-generated)
```yaml
references:
  - type: bib
    number: 7
    title: "Reference Title"
    link: "[[0007_bib_Title]]"
  - type: note
    number: 12
    title: "Note Title"
    link: "[[0012_note_Title]]"
```

## Linking Syntax

### Wiki-Style (Recommended)
```markdown
See [[0001_note_Topic_Name]] for more details.
Related to [[0007_bib_Book_Title]].
```

### Markdown Style
```markdown
See [Topic Name](../03-Consolidated/0001_note_Topic_Name.md).
```

## Timestamp Formats

### Interactive Creation
```
Date (YYYY-MM-DD) [today]: 2025-10-10
Time options:
  1 = now (current time)
  2 = custom (you specify HH:MM:SS)
  3 = unknown (99-99-99)
  4 = none (date only)
```

### Format Examples
```
Full:     2025-10-10_14-30-45
Partial:  2025-10-10_14-30
Date:     2025-10-10
Unknown:  2025-10-10_99-99-99
```

## Typical Workflows

### Morning Routine
```vim
<leader>nq          " Quick capture thoughts
[write morning thoughts]
:w                  " Save
```

### Research Session
```vim
<leader>nn          " New note (type: note, title: Research Topic)
[write content]
<leader>nc          " Insert citation
[select bibliography entry]
<leader>nl          " Link to related note
[select note]
:w
```

### End of Day
```vim
<leader>nr          " Review today's journals
<leader>nt          " Browse by today's tags
<leader>nq          " Final capture
<leader>nx          " Convert scratchpad to journal
```

### Converting Captures
```vim
" Open scratchpad with content
<leader>nx          " Convert note
" Choose: journal
" Confirm timestamp
" Delete original: n
```

## Search Patterns

### Basic Search
```vim
:PKMSearch philosophy
:PKMSearch "exact phrase"
```

### By Tag
```vim
:PKMBrowseTags
" Select tag
" Select file
```

### By Date
```vim
:PKMRecentJournals  " Last 10 entries
```

## Common Tasks

### Create Bibliography Entry
```vim
<leader>nn          " New note
" Type: bib
" Title: [Book Title]
" Author: [Author Name]
" Source type: book
" Source location: /path/to/book.pdf
```

### Link Two Notes
```vim
" In note A
<leader>nl          " Link note
" Select note B
" Creates: [[note_B_basename]]

" In note B
<leader>nb          " Show backlinks
" Shows: note A
```

### Update All References
```vim
" After adding many citations
:PKMUpdateReferences
" Scans document
" Updates frontmatter
```

## Keyboard Shortcuts Summary

| Key | Action | Context |
|-----|--------|---------|
| `<leader>nn` | New note | Any |
| `<leader>nj` | New journal | Any |
| `<leader>nq` | Quick capture | Any |
| `<leader>nx` | Convert note | In scratchpad |
| `<leader>nc` | Insert citation | In note |
| `<leader>ng` | Go to citation | On citation |
| `<leader>nl` | Link note | In note |
| `gf` | Follow link | On link |
| `<leader>nb` | Backlinks | In note |
| `<leader>nf` | Search | Any |
| `<leader>nt` | Browse tags | Any |
| `<leader>nr` | Recent journals | Any |
| `K` | Preview citation | On citation |

## Status Values

```yaml
status: draft       # Initial creation
status: incubation  # Developing ideas
status: mature      # Well-developed, stable
```

## Tag Conventions

### Suggested Structure
```yaml
tags:
  - domain/philosophy      # Domain classification
  - topic/ethics          # Topic classification
  - type/synthesis        # Note type
  - status/wip            # Work in progress
```

### Common Tags
```yaml
tags:
  - reflection            # Personal reflection
  - research              # Research notes
  - summary               # Summary of source
  - idea                  # Original idea
  - todo                  # Needs work
  - important             # High priority
```

## Troubleshooting Quick Fixes

### Command not found
```vim
:lua print(vim.inspect(require('pkm')))
" If error: check file locations
```

### Path issues
```vim
:lua print(package.config:sub(1,1))
" Should show: \ (Windows) or / (Linux)
```

### Frontmatter errors
```vim
:PKMValidateFrontmatter
" Shows missing/invalid fields
```

### Citation not working
```vim
:lua require('pkm.citations').validate_citations()
" Shows invalid citations
```

### Can't find notes
```vim
:PKMStats
" Shows note counts
" If 0: check root_path in setup
```

## Configuration Snippet

### Minimal Setup
```lua
require('pkm').setup({
  root_path = vim.fn.has('win32') == 1 and "P:/Notes" or "/mnt/p/Notes",
  keymaps = {
    quick_capture = "<leader>nq",
    new_note = "<leader>nn",
    search = "<leader>nf",
  }
})
```

### Full Setup
```lua
require('pkm').setup({
  root_path = "P:/Notes",
  folders = {
    scratchpad = "01-Scratchpad",
    journal = "02-Journal",
    consolidated = "03-Consolidated",
  },
  frontmatter_templates = {
    consolidated = { author = "Your Name" },
  },
  keymaps = {
    new_note = "<leader>nn",
    new_journal = "<leader>nj",
    quick_capture = "<leader>nq",
    -- ... full list in Integration Guide
  }
})
```

## Quick Tips

1. **Use Quick Capture liberally** - `<leader>nq` is your friend
2. **Convert later** - Capture fast, organize later
3. **Link as you write** - `<leader>nl` builds your knowledge graph
4. **Tag consistently** - Decide on conventions early
5. **Review regularly** - `<leader>nr` and `<leader>nt`
6. **Update references** - After adding citations
7. **Validate periodically** - `:PKMValidateFrontmatter`
8. **Backup regularly** - Plain text = easy backups

## One-Minute Test

```vim
:PKMQuickCapture           " Capture
This is a test             " Write
<Esc>:w:q                  " Save and quit
:PKMRecentJournals         " Should show entry
```

If that works, you're all set! 🎉

---

**Print this card or keep it handy while learning the system.**
