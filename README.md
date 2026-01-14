# PKM.nvim

Personal Knowledge Management system for Neovim with multi-wiki support.

## Features

- 📚 Multiple independent wikis
- 🔗 Bidirectional linking with citation permissions
- 📝 YAML frontmatter management
- ⏱️ Flexible timestamp handling
- 🔍 Search and tag browsing
- 🖥️ Cross-platform (Windows, WSL, Linux, macOS)

## Installation

### Lazy.nvim
```lua
{
  'yourusername/pkm.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim',  -- Optional but recommended
  },
  config = function()
    require('pkm').setup({
      -- Your configuration here
    })
  end
}
```

### Packer
```lua
use {
  'yourusername/pkm.nvim',
  requires = {'nvim-telescope/telescope.nvim'},
  config = function()
    require('pkm').setup({})
  end
}
```

## Quick Start
```lua
require('pkm').setup({
  root_path = vim.fn.expand('~/Notes'),  -- Your notes directory
  user = {
    name = "Your Name",
  },
  keymaps = {
    new_note = "<leader>nn",
    new_journal = "<leader>nj",
    quick_capture = "<leader>nq",
  }
})
```

## Documentation

See `:help pkm` after installation.

## Status

🚧 **Active Development** - This plugin is functional but still evolving.

Current version handles:
- ✅ Note creation and management
- ✅ Citations and references
- ✅ YAML frontmatter
- ✅ Bidirectional linking
- ✅ Cross-platform support

Coming soon:
- 🔜 Multi-wiki system
- 🔜 Telescope integration
- 🔜 Markdown preview
- 🔜 Graph visualization

## License

MIT License - see [LICENSE](LICENSE) file.

## Contributing

This is a personal project, but feedback and suggestions are welcome!
