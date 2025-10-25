# PKM System - Complete Setup Guide

## Quick Start

### 1. Basic Configuration

Add to your `init.lua` (after your plugin setup):

```lua
-- Detect OS and set path
local pkm_root
if vim.fn.has('win32') == 1 then
  pkm_root = "P:/Notes"
else
  pkm_root = "/mnt/p/Notes"
end

-- Setup PKM with automatic timestamps
require('pkm').setup({
  root_path = pkm_root,
  
  -- User information (appears in author fields)
  user = {
    name = "Your Name",
    email = "your.email@example.com", -- optional
    institution = "Your Institution", -- optional
  },
  
  -- Timestamp behavior (all optional - these are defaults)
  timestamp = {
    default_format = "full", -- full, date_time, date_only
    auto_timestamp = true, -- Auto-use current time (no prompts)
    prompt_on_create = false, -- Set true to always prompt
  },
  
  -- Keybindings
  keymaps = {
    quick_capture = "<leader>nq",
    new_note = "<leader>nn",
    new_journal = "<leader>nj",
    insert_citation = "<leader>nc",
    search = "<leader>nf",
  }
})

-- Optional: Auto-update last_updated_on on save
require('pkm.yaml').setup_auto_update()
```

### 2. Create Note Directories

```bash
# Windows
mkdir P:\Notes\01-Scratchpad
mkdir P:\Notes\02-Journal
mkdir P:\Notes\03-Consolidated

# Linux/WSL
mkdir -p /mnt/p/Notes/{01-Scratchpad,02-Journal,03-Consolidated}
```

### 3. Test the System

```vim
:PKMQuickCapture  " Create a quick note
:PKMStats         " View statistics
```

## Configuration Options

### Timestamp Formats

| Format | Example | Use Case |
|--------|---------|----------|
| `full` | `2025-10-10_13-48-13` | Default, most precise |
| `date_time` | `2025-10-10_13-48` | Without seconds |
| `date_only` | `2025-10-10` | Date-only notes |

### Changing Timestamp Behavior

```lua
-- In your setup:
timestamp = {
  default_format = "full",      -- Change to: date_time or date_only
  auto_timestamp = true,        -- false = always prompt
  prompt_on_create = false,     -- true = always ask for time
}
```

### Runtime Timestamp Configuration

```vim
" Toggle auto-timestamp on/off
:PKMToggleAutoTimestamp

" Change default format for this session
:PKMSetDefaultFormat full
:PKMSetDefaultFormat date_time
:PKMSetDefaultFormat date_only
```

## Frontmatter Templates

### Journal Entry

```yaml
---
created_on: 2025-10-10T13:48:13
last_updated_on: 2025-10-10T13:48:13
author: Your Name
tags:
  - reflection
  - personal
location: Home
---
```

### Consolidated Note

```yaml
---
title: "Note Title"
author: Your Name
created_on: 2025-10-10T13:48:13
last_updated_on: 2025-10-10T13:48:13
tags:
  - topic
  - domain
status: draft
references: []
notes: []
---
```

### Bibliography Entry

```yaml
---
title: "Source Title"
source_author: Original Author
note_author: Your Name
created_on: 2025-10-10T13:48:13
last_updated_on: 2025-10-10T13:48:13
citation: "@book{key2025, title={...}, author={...}, year={2025}}"
source_type: book
source_location: "/path/to/file.pdf"
tags:
  - philosophy
---
```

### Scratchpad

```yaml
---
created_on: 2025-10-10T13:48:13
last_updated_on: 2025-10-10T13:48:13
---
```

## Advanced Configuration

### Custom Templates

```lua
require('pkm').setup({
  -- ... other config ...
  
  frontmatter_templates = {
    journal = {
      created_on = "ISO8601",
      last_updated_on = "ISO8601",
      author = "Your Name",
      tags = {},
      mood = "", -- Add custom fields
      weather = "",
    },
  }
})
```

### Per-Project Configuration

```lua
-- Different configs for different note collections
local configs = {
  personal = {
    root_path = "~/Notes/Personal",
    user = {name = "Your Name"},
  },
  work = {
    root_path = "~/Notes/Work",
    user = {name = "Professional Name", institution = "Company"},
  }
}

-- Switch projects
vim.api.nvim_create_user_command('NotesPersonal', function()
  require('pkm').setup(configs.personal)
end, {})

vim.api.nvim_create_user_command('NotesWork', function()
  require('pkm').setup(configs.work)
end, {})
```

### Automatic Last Modified Update

```lua
-- Add to your setup to auto-update last_updated_on on save
require('pkm.yaml').setup_auto_update()
```

This creates an autocmd that updates the `last_updated_on` field every time you save a note.

## Workflow Examples

### Daily Journal

```vim
" Morning routine
<leader>nj          " Create today's journal
[write thoughts]
:w                  " Save (auto-updates last_updated_on)
```

### Research Notes

```vim
" Create bibliography entry
<leader>nn          " New note
" Select: bib
" Fill in source details

" Create research note
<leader>nn          " New note  
" Select: note
" Write content
<leader>nc          " Insert citation to bibliography
```

### Quick Capture

```vim
<leader>nq          " Quick capture
[write idea]
:w

" Later: convert to journal or note
<leader>nx          " Convert note
```

## Troubleshooting

### Timestamps Always Prompt

Check your config:

```lua
timestamp = {
  auto_timestamp = true,    -- Should be true
  prompt_on_create = false, -- Should be false
}
```

### Author Field Empty

Make sure you set `user.name`:

```lua
user = {
  name = "Your Name",  -- This fills author fields automatically
}
```

### Last Updated Not Updating

Enable auto-update:

```lua
-- Add after setup
require('pkm.yaml').setup_auto_update()
```

Or manually update:

```vim
:PKMUpdateTimestamp
```

## Migration Guide

### From Old Notes

If you have existing notes without proper frontmatter:

1. Open the note
2. Add frontmatter manually or use:

```vim
:PKMUpdateFrontmatter
```

### From Google Docs Journals

The system can parse old format: `Journal backup 2025-2-2.gdoc`

Just convert to `.md` and the timestamp parser will handle it.

## Next Steps

1. **Customize templates** to match your workflow
2. **Set up keybindings** that feel natural
3. **Enable auto-update** for last_updated_on
4. **Create your first notes** and build your knowledge base

For more examples, see `config/setup.md` in the PKM directory.
