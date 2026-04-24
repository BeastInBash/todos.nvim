# todos.nvim

---

![Todo Plugin Demo](./assets/todo-nvim.gif)

---

A production-grade TODO manager for Neovim with a **Rose Pine Moon** themed (default) floating UI,
project/global scoping, full JSON persistence, and a **live Markdown editor** for descriptions powered by [markview.nvim](https://github.com/OXY2DEV/markview.nvim).

---

## Features

- **Dual scope** — project-level (`.nvim/todo.json`) and global (`~/.local/share/nvim/todo/global.json`)
- **Auto project root detection** — looks for `.git`, `package.json`, `Cargo.toml`, `go.mod`, etc.
- **Rose Pine Moon** colour palette by default — fully overridable with any hex colours
- **Split floating window** — list panel on the left, live detail panel on the right
- **Full CRUD** — add / edit / delete / toggle status / cycle priority / reorder
- **Markdown descriptions** — full multi-line Markdown editor with live rendering via markview.nvim
- **Persistent JSON storage** — atomic writes, graceful corruption handling
- **Lazy-load friendly** — zero cost until first use

---

## Requirements

- Neovim `>= 0.9`
- [markview.nvim](https://github.com/OXY2DEV/markview.nvim) *(optional but recommended — enables live Markdown rendering in descriptions)*

---

## Installation

### lazy.nvim

```lua
-- Recommended: install markview.nvim alongside
{
  "OXY2DEV/markview.nvim",
  lazy = false,
},

{
  "BeastInBash/todos.nvim",
  event = "VeryLazy",
  keys = {
    { "<leader>td", desc = "Todo: Open UI" },
    { "<leader>ta", desc = "Todo: Add" },
    { "<leader>tt", desc = "Todo: Toggle" },
    { "<leader>ts", desc = "Todo: Switch scope" },
  },
  config = function()
    require("todo-nvim").setup({
      -- default scope when opening: "project" | "global"
      default_scope = "project",

      -- storage paths (optional overrides)
      storage = {
        global_path      = vim.fn.stdpath("data") .. "/todo/global.json",
        project_filename = ".nvim/todo.json",
      },

      -- floating window proportions
      ui = {
        width       = 0.8,   -- fraction of editor width
        height      = 0.8,   -- fraction of editor height
        border      = "rounded",
        split_ratio = 0.4,   -- left panel fraction
      },

      -- global keymaps (outside the window)
      keymaps = {
        open   = "<leader>td",
        add    = "<leader>ta",
        toggle = "<leader>tt",
        scope  = "<leader>ts",
      },

      -- in-panel keymaps
      panel_keymaps = {
        add       = "a",
        delete    = "d",
        edit      = "e",
        toggle    = "<CR>",
        close     = "q",
        scope     = "s",
        next_prio = "p",
        move_down = "J",
        move_up   = "K",
        help      = "?",
      },

      -- optional: override any colours (Rose Pine Moon used by default)
      colors = {
        base    = "#1e1e2e",
        surface = "#181825",
        overlay = "#313244",
        text    = "#cdd6f4",
        iris    = "#cba6f7",
        pine    = "#89b4fa",
        foam    = "#94e2d5",
        love    = "#f38ba8",
        gold    = "#f9e2af",
        muted   = "#585b70",
        subtle  = "#6c7086",
        highlight_med = "#45475a",
      },
    })
  end,
},
```

> **Note:** The `colors` key is optional. You only need to specify the keys you want to override — the rest default to Rose Pine Moon.

### packer.nvim

```lua
use {
  "BeastInBash/todos.nvim",
  config = function()
    require("todo-nvim").setup()
  end,
}
```

---

## Commands

| Command | Description |
|---|---|
| `:TodoOpen` | Open the full floating UI |
| `:TodoAdd [title]` | Quick-add a TODO (optional inline title) |
| `:TodoToggle` | Toggle status of the currently selected TODO |
| `:TodoScope [global\|project]` | Switch scope, or toggle if no arg given |

---

## In-panel Keymaps

| Key | Action |
|---|---|
| `j` / `k` | Navigate list |
| `a` | Add new TODO |
| `d` | Delete selected TODO |
| `e` | Edit selected TODO |
| `<CR>` | Toggle status (`pending` → `in_progress` → `done` → …) |
| `p` | Cycle priority (`low` → `medium` → `high` → …) |
| `v` | Open full-screen Markdown preview of description |
| `J` / `K` | Move item down / up in list |
| `s` | Switch scope |
| `q` / `<Esc>` | Close |
| `?` | Show help overlay |
| `gg` / `G` | Jump to top / bottom |

---

## Markdown Descriptions

Every TODO has a **multi-line Markdown description** edited in a dedicated floating buffer.

When you press `a` (add) or `e` (edit), the flow is:

1. **Title + priority** — entered via a quick prompt
2. **Description** — a proper floating editor opens with `filetype=markdown`

If you have [markview.nvim](https://github.com/OXY2DEV/markview.nvim) installed, it attaches automatically and **renders your Markdown live** as you type — headers, lists, code blocks, bold/italic, tables, and more.

### Editor keymaps

| Key | Action |
|---|---|
| `<leader>w` | Save and close (normal + insert mode) |
| `<C-s>` | Save and close (normal + insert mode) |
| `:w` | Save and close |
| `q` / `<Esc>` | Cancel (normal mode) |
| `<Esc><Esc>` | Cancel (from insert mode) |

### Full-screen preview

Press `v` on any TODO in the list to open its description in a read-only fullscreen Markdown preview window. markview renders it here too.

---

## Colour Customization

The `colors` table in `setup()` maps semantic roles to hex values.
You only need to specify keys you want to change — all others fall back to **Rose Pine Moon**.

```lua
require("todo-nvim").setup({
  colors = {
    base  = "#1e1e2e",  -- window background
    text  = "#cdd6f4",  -- default text
    iris  = "#cba6f7",  -- borders, keys, scope badge
    pine  = "#89b4fa",  -- headers
    foam  = "#94e2d5",  -- "done" status
    love  = "#f38ba8",  -- high priority
    gold  = "#f9e2af",  -- in-progress, medium priority
    muted = "#585b70",  -- muted text, low priority
    -- ... etc
  },
})
```

### Available colour keys

| Key | Role |
|---|---|
| `base` | Window background |
| `surface` | Header background |
| `overlay` | Selected item background |
| `text` | Default text |
| `muted` | Muted / low-priority / done text |
| `subtle` | Subtle text, pending status |
| `iris` | Borders, detail keys, scope badge |
| `pine` | Panel headers, global scope badge |
| `foam` | Done status |
| `love` | High priority |
| `gold` | In-progress status, medium priority |
| `rose` | (reserved for future use) |
| `highlight_med` | Separators |

---

## TODO Structure

```json
{
  "id":          "a1b2c3d4",
  "title":       "Implement auth module",
  "description": "## Notes\n\n- OAuth2 + JWT\n- See [design doc](./docs/auth.md)\n\n```lua\nlocal token = jwt.sign(payload)\n```",
  "status":      "in_progress",
  "priority":    "high",
  "created_at":  "2025-04-24T10:00:00",
  "updated_at":  "2025-04-24T12:30:00"
}
```

`description` is stored as a plain string with `\n` for newlines — full Markdown is supported.

**Valid status values:** `pending`, `in_progress`, `done`
**Valid priority values:** `low`, `medium`, `high`

---

## Storage Layout

```
~/.local/share/nvim/todo/global.json    ← global todos (shared across all projects)
<project_root>/.nvim/todo.json          ← project-scoped todos
```

- Files are created automatically on first write
- Corrupted JSON is detected and replaced with an empty list (a warning is shown)
- Writes are atomic: data is written to a `.tmp` file first, then renamed into place

---

## Architecture

```
lua/todo-nvim/
├── init.lua      — setup(), config defaults, global keymaps
├── ui.lua        — floating window, rendering, panel keymaps
├── editor.lua    — Markdown description editor + preview (markview integration)
├── storage.lua   — JSON read/write, CRUD operations
├── commands.lua  — :Todo* user commands
└── utils.lua     — shared helpers (timestamps, IDs, string ops, icons)
```

### Module responsibilities

**`init.lua`** — the only file users touch. Calls `setup()`, merges user config over defaults, registers global keymaps and commands.

**`ui.lua`** — all floating window logic: two content windows (list + detail) inside a decorative border window, pure-function rendering via extmark highlights, cursor sync, panel keymaps.

**`editor.lua`** — opens a proper editable `ft=markdown` scratch buffer for writing descriptions. markview attaches automatically. Exposes `open_editor(opts)` and `preview_description(text)`.

**`storage.lua`** — atomic JSON reads and writes, full CRUD (add / update / delete / reorder), scope-aware path resolution, corruption recovery.

**`utils.lua`** — timestamps, short UUID generation, string helpers (truncate, pad, center, word-wrap), status/priority icons, JSON pretty-printer.

---

## Extending the Plugin

The data model is forward-compatible — just add new fields in `storage.add` / `storage.update` and render them in `ui.lua`. Planned extension points:

```lua
-- Tags (future)
tags = { "backend", "auth" }

-- Deadlines (future)
deadline = "2025-05-01"

-- Assignees (future)
assignee = "alice"
```
