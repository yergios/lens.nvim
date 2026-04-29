# lens.nvim

Lens.nvim lets you pin highlights to any visual selection so you can track important lines and symbols while reading code. Highlights persist across cursor moves and survive mode changes until you explicitly remove them.

## Installation

**lazy.nvim**

```lua
{
  'yergios/lens.nvim',
  event = 'VeryLazy',
  config = function()
    require('lens').setup()
  end,
}
```

**LazyVim** — use the built-in keymap spec to skip manual keymap setup:

```lua
{
  'yergios/lens.nvim',
  keys = require('lens').keys,
}
```

## Usage

1. Select text in any visual mode (`v`, `V`, or `<C-v>`).
2. Press `<leader>l` to pin the highlight.
3. Move the cursor onto a highlight and press `<leader>l` to remove it.
4. Press `<leader>L` to clear every highlight in every buffer.

Attempting to pin the same selection twice is a no-op.

> **Block mode note:** `<C-v>` selections highlight each line from column 0 to the full visual width of the window, ignoring the block's column bounds. Use `v` for column-precise ranges.

## Configuration

Pass options to `setup()`. All fields are optional.

```lua
require('lens').setup({
  -- Highlight group applied to pinned selections.
  -- Defaults to 'LensHighlight', which is auto-created from your 'Visual' colors.
  -- Set this to an existing group name to take full control of appearance.
  highlight_group = 'LensHighlight',

  -- Appearance overrides — only used when highlight_group == 'LensHighlight'.
  bg        = nil,     -- hex number, e.g. 0xff0000
  fg        = nil,
  bold      = false,
  italic    = false,
  underline = false,

  -- Set to false to skip keymap registration (manage keys yourself).
  setup_keymaps = true,
  add_key       = '<leader>l',
  remove_key    = '<leader>l',
  clear_all_key = '<leader>L',
})
```

## Keymaps

| Mode   | Key          | Action                          |
|--------|--------------|---------------------------------|
| Visual | `<leader>l`  | Pin highlight to selection      |
| Normal | `<leader>l`  | Remove highlight under cursor   |
| Normal | `<leader>L`  | Clear all highlights            |

## API

```lua
local lens = require('lens')

-- Pin a highlight programmatically (0-indexed lines, 0-indexed cols, end_col exclusive).
lens.add_highlight(bufnr, start_line, start_col, end_line, end_col, key)

-- Remove a highlight by the key returned above.
lens.remove_highlight(key)

-- Remove the highlight that covers the current cursor position.
lens.remove_highlight_at_cursor()

-- Remove every highlight in every buffer.
lens.clear_all()
```
