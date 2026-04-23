# todos.nvim

---

![Todo Plugin Demo](./assets/todo-nvim.gif)

---
A TODO manager for Neovim with a Rose Pine-themed(default) floating UI,
project/global scoping, and full JSON persistence.

---

## Features

- **Dual scope**: project-level (`.nvim/todo.json`) and global (`~/.local/share/nvim/todo/global.json`)  
- **Auto project root detection**: looks for `.git`, `package.json`, `Cargo.toml`, `go.mod`, etc.  
- **Rose Pine Moon** colour palette with custom highlight groups  
- **Split floating window** — list on the left, detail panel on the right  
- **Full CRUD**: add / edit / delete / toggle status / cycle priority  
- **Persistent JSON storage** with atomic writes and graceful corruption handling  
- **Lazy-load friendly** — zero cost until first use  

---

## Installation

### lazy.nvim

```lua
{
  "BeastInBash/todos.nvim",                     -- replace with real repo
  event = "VeryLazy",                  -- lazy-load on first real event
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
      color = {
        base    = "#1e1e2e",   -- Catppuccin Mocha base
        surface = "#181825",
        overlay = "#313244",
        text    = "#cdd6f4",
        iris    = "#cba6f7",   -- mauve
        pine    = "#89b4fa",   -- blue
        foam    = "#94e2d5",   -- teal
        love    = "#f38ba8",   -- red
        gold    = "#f9e2af",   -- yellow
        muted   = "#585b70",
        subtle  = "#6c7086",
        highlight_med = "#45475a",
      }
    })
  end,
},
```

### packer.nvim

```lua
use {
  "BeastInBash/todos.nvim",
  config = function()
    require("todo.nvim").setup()
  end,
}
```

---

## Commands

| Command                    | Description                                  |
|---------------------------|----------------------------------------------|
| `:TodoOpen`                | Open the full floating UI                    |
| `:TodoAdd [title]`         | Quick-add a TODO (optional inline title)      |
| `:TodoToggle`              | Toggle status of the currently selected TODO |
| `:TodoScope [global\|project]` | Switch scope or toggle if no arg given   |

---

## In-panel Keymaps

| Key        | Action                         |
|------------|-------------------------------|
| `j` / `k`  | Navigate list                  |
| `a`        | Add new TODO                   |
| `d`        | Delete selected TODO           |
| `e`        | Edit selected TODO             |
| `<CR>`     | Toggle status (pending → in_progress → done → …) |
| `p`        | Cycle priority (low → medium → high → …)         |
| `J` / `K`  | Move item down / up in list    |
| `s`        | Switch scope                   |
| `q` / `<Esc>` | Close                      |
| `?`        | Show help overlay              |
| `gg` / `G` | Jump to top / bottom           |

---

## TODO Structure

```json
{
  "id":          "a1b2c3d4",
  "title":       "Implement auth module",
  "description": "OAuth2 + JWT, see design doc",
  "status":      "in_progress",
  "priority":    "high",
  "created_at":  "2025-04-24T10:00:00",
  "updated_at":  "2025-04-24T12:30:00"
}
```

Valid status values: `pending`, `in_progress`, `done`  
Valid priority values: `low`, `medium`, `high`

---

## Storage Layout

```
~/.local/share/nvim/todo/global.json    ← global todos
<project_root>/.nvim/todo.json          ← project todos
```

Files are created automatically on first write.  
Corrupted JSON is detected and replaced with an empty list (with a warning).  
Writes are atomic: written to a `.tmp` file first, then renamed.

---

## Colour Palette (Rose Pine Moon)

| Role            | Colour     |
|-----------------|-----------|
| Background      | `#232136`  |
| Surface         | `#2a273f`  |
| Overlay (sel)   | `#393552`  |
| Muted text      | `#6e6a86`  |
| Subtle text     | `#908caa`  |
| Default text    | `#e0def4`  |
| Love (high prio)| `#eb6f92`  |
| Gold (in prog)  | `#f6c177`  |
| Pine (header)   | `#3e8fb0`  |
| Foam (done)     | `#9ccfd8`  |
| Iris (border)   | `#c4a7e7`  |

---

## Architecture

```
lua/todo-nvim/
├── init.lua      — setup(), config defaults, global keymaps
├── ui.lua        — floating window, rendering, panel keymaps
├── storage.lua   — JSON read/write, CRUD operations
├── commands.lua  — :Todo* user commands
└── utils.lua     — shared helpers (time, IDs, string ops, icons)
```

---
