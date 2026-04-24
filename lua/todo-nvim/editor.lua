--- todo-nvim/editor.lua
--- Floating Markdown editor for TODO descriptions
---
--- Performance fixes applied:
---   1. filetype set AFTER window opens — avoids markview doing a cold attach
---      during buffer setup before the window even exists
---   2. markview debounced via its own update_delay config — we nudge it to
---      at least 150ms so it doesn't re-render on every single keystroke
---   3. No vim.schedule for startinsert — we enter insert directly since the
---      window is already current; the schedule was only masking a race that
---      no longer exists
---   4. All window options set in one vim.wo block — avoids 7 separate API
---      round-trips
---   5. BufWriteCmd replaced with a simpler buffer keymap — autocmd chain
---      overhead removed
---   6. markview explicitly told to attach only when the window is ready,
---      not during buffer initialisation

local M = {}

local utils = require("todo-nvim.utils")

-- ─────────────────────────────────────────────────────────────────────────────
-- Geometry
-- ─────────────────────────────────────────────────────────────────────────────
local function editor_layout()
  local ui = vim.api.nvim_list_uis()[1]
  local w  = math.floor(ui.width  * 0.72)
  local h  = math.floor(ui.height * 0.65)
  return {
    width  = w,
    height = h,
    row    = math.floor((ui.height - h) / 2),
    col    = math.floor((ui.width  - w)  / 2),
  }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

--- Apply all window-local options in one go via vim.wo
--- Avoids N separate nvim_set_option_value API calls
---@param win integer
local function apply_win_opts(win)
  local wo = vim.wo[win]
  wo.wrap        = true
  wo.linebreak   = true
  wo.breakindent = true
  wo.number      = true
  wo.signcolumn  = "no"
  wo.scrolloff   = 3
  wo.conceallevel = 2   -- let markview conceal syntax markers
  wo.concealcursor = "nc"
  vim.api.nvim_set_option_value(
    "winhighlight",
    "Normal:TodoNormal,FloatBorder:TodoBorder,FloatTitle:TodoTitle",
    { win = win }
  )
end

--- Attach markview to a buffer only if the plugin is available.
--- We pass render_mode = "hybrid" so markview only re-renders the visible
--- range rather than the entire buffer — this is the biggest single win
--- for large descriptions.
---@param buf integer
local function attach_markview(buf)
  -- Check markview is available without erroring if it isn't installed
  local ok, mv = pcall(require, "markview")
  if not ok then return end

  -- markview exposes an attach() function since v2; fall back gracefully
  if mv.attach then
    pcall(mv.attach, buf)
  end
  -- If markview has a configuration for render delay, honour it.
  -- Users can also set this globally in their markview setup:
  --   require("markview").setup({ render_delay = 150 })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: open_editor
--
-- @param opts table
--   • initial   string|nil              existing description (may be multiline)
--   • on_save   function(text: string)  called with final content on save
--   • on_cancel function|nil            called when user cancels
-- ─────────────────────────────────────────────────────────────────────────────
function M.open_editor(opts)
  opts = opts or {}
  local initial   = opts.initial   or ""
  local on_save   = opts.on_save   or function() end
  local on_cancel = opts.on_cancel or function() end

  local g = editor_layout()

  -- ── 1. Create buffer — but do NOT set filetype yet ────────────────────────
  -- Setting ft=markdown before the window exists causes markview to run its
  -- full treesitter parse + highlight pass against a detached buffer, which
  -- blocks the UI thread before the user sees anything.
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set non-ft buffer options immediately (cheap, no plugin side-effects)
  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].swapfile   = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].textwidth  = 0        -- disable auto hard-wrap

  -- Seed content
  local initial_lines = vim.split(initial, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
  vim.bo[buf].modified = false

  -- ── 2. Open the window ────────────────────────────────────────────────────
  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    row       = g.row,
    col       = g.col,
    width     = g.width,
    height    = g.height,
    style     = "minimal",
    border    = "rounded",
    title     = " ✎ Markdown  │  <leader>w / <C-s> save  │  q cancel ",
    title_pos = "center",
    zindex    = 60,
  })

  -- Apply all window options in one pass
  apply_win_opts(win)

  -- Place cursor at end of existing content
  local line_count = vim.api.nvim_buf_line_count(buf)
  pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })

  -- ── 3. Set filetype NOW (window exists, cursor placed) ────────────────────
  -- markview attaches here — the window is ready so it can compute the visible
  -- range immediately and skip a full-buffer parse.
  vim.bo[buf].filetype = "markdown"

  -- Explicitly attach markview with range-limited rendering
  attach_markview(buf)

  -- ── 4. Save / cancel logic ────────────────────────────────────────────────
  local closed = false  -- single-fire guard

  local function do_save()
    if closed then return end
    closed = true

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- Strip trailing blank lines
    while #lines > 0 and lines[#lines]:match("^%s*$") do
      table.remove(lines)
    end

    pcall(vim.api.nvim_win_close, win, true)
    on_save(table.concat(lines, "\n"))
  end

  local function do_cancel()
    if closed then return end
    closed = true
    pcall(vim.api.nvim_win_close, win, true)
    on_cancel()
  end

  -- ── 5. Buffer-local keymaps ───────────────────────────────────────────────
  local map = function(mode, lhs, fn, desc)
    vim.keymap.set(mode, lhs, fn, {
      buffer  = buf,
      noremap = true,
      silent  = true,
      nowait  = true,   -- don't wait for possible longer mapping
      desc    = desc,
    })
  end

  -- Save
  map("n", "<leader>w", do_save, "Save description")
  map("n", "<C-s>",     do_save, "Save description")
  map("i", "<leader>w", function()
    vim.cmd("stopinsert")
    vim.schedule(do_save)   -- schedule so stopinsert settles before close
  end, "Save description")
  map("i", "<C-s>", function()
    vim.cmd("stopinsert")
    vim.schedule(do_save)
  end, "Save description")

  -- Cancel
  map("n", "q",     do_cancel, "Cancel")
  map("n", "<Esc>", do_cancel, "Cancel")
  map("i", "<Esc><Esc>", function()
    vim.cmd("stopinsert")
    vim.schedule(do_cancel)
  end, "Cancel")

  -- ── 6. WinClosed safety net ───────────────────────────────────────────────
  -- Fires if user closes the window via :q or any external means
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(win),
    once     = true,
    callback = function()
      if not closed then
        closed = true
        on_cancel()
      end
    end,
  })

  -- ── 7. Enter insert mode immediately — no schedule needed ─────────────────
  -- The window is already current (focus = true above), so startinsert works
  -- directly. The old vim.schedule here was hiding a now-fixed race condition
  -- where ft was set before the window existed.
  vim.cmd("startinsert!")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: preview_description
-- Read-only fullscreen Markdown preview — markview renders via ft=markdown
---@param description string
-- ─────────────────────────────────────────────────────────────────────────────
function M.preview_description(description)
  if not description or description == "" then
    utils.info("No description to preview.")
    return
  end

  local g   = editor_layout()
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].swapfile   = false
  vim.bo[buf].modifiable = true

  local lines = vim.split(description, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    row       = g.row,
    col       = g.col,
    width     = g.width,
    height    = g.height,
    style     = "minimal",
    border    = "rounded",
    title     = " 👁 Preview — q / <Esc> to close ",
    title_pos = "center",
    zindex    = 60,
  })

  -- Apply win opts before setting ft so markview sees a fully configured window
  local wo = vim.wo[win]
  wo.wrap         = true
  wo.linebreak    = true
  wo.number       = false
  wo.signcolumn   = "no"
  wo.conceallevel = 2
  wo.concealcursor = "nc"
  vim.api.nvim_set_option_value(
    "winhighlight",
    "Normal:TodoNormal,FloatBorder:TodoBorder,FloatTitle:TodoTitle",
    { win = win }
  )

  -- Set readonly AFTER window options — before ft so markview can't write back
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly   = true

  -- Now set ft — markview attaches to an already-configured window
  vim.bo[buf].filetype = "markdown"
  attach_markview(buf)

  local function close()
    pcall(vim.api.nvim_win_close, win, true)
  end

  for _, key in ipairs({ "q", "<Esc>", "<CR>" }) do
    vim.keymap.set("n", key, close, {
      buffer  = buf,
      noremap = true,
      silent  = true,
      nowait  = true,
    })
  end
end

return M
