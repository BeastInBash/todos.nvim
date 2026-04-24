--- todo-nvim/ui.lua
--- Full floating-window UI for the todo manager
--- Rose Pine color palette, split panel layout
--- Colors are fully user-overridable via setup({ colors = { ... } })

local M = {}

local storage = require("todo-nvim.storage")
local utils   = require("todo-nvim.utils")
local editor  = require("todo-nvim.editor")

-- ─────────────────────────────────────────────────────────────────────────────
-- Default Rose Pine Moon palette
-- Used as fallback when no colors are passed to setup_highlights()
-- ─────────────────────────────────────────────────────────────────────────────
local DEFAULT_COLORS = {
  base           = "#232136",
  surface        = "#2a273f",
  overlay        = "#393552",
  muted          = "#6e6a86",
  subtle         = "#908caa",
  text           = "#e0def4",
  love           = "#eb6f92",
  gold           = "#f6c177",
  rose           = "#ea9a97",
  pine           = "#3e8fb0",
  foam           = "#9ccfd8",
  iris           = "#c4a7e7",
  highlight_low  = "#2a283e",
  highlight_med  = "#44415a",
  highlight_high = "#56526e",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Highlight definitions
-- Accepts an optional colors table; falls back to Rose Pine Moon defaults.
-- Call this from setup() and again from M.open() to ensure highlights
-- are always in sync with the user's config.
-- ─────────────────────────────────────────────────────────────────────────────
function M.setup_highlights(colors)
  -- Merge user colors over defaults — user only needs to specify what changes
  local c = vim.tbl_extend("force", DEFAULT_COLORS, colors or {})

  local hl = function(name, opts)
    vim.api.nvim_set_hl(0, name, opts)
  end

  -- Window chrome
  hl("TodoNormal",          { fg = c.text,          bg = c.base })
  hl("TodoBorder",          { fg = c.iris,           bg = c.base })
  hl("TodoTitle",           { fg = c.iris,           bg = c.base,    bold = true })
  hl("TodoHeader",          { fg = c.pine,           bg = c.surface, bold = true })
  hl("TodoSeparator",       { fg = c.highlight_med,  bg = c.base })
  hl("TodoFooter",          { fg = c.muted,          bg = c.base,    italic = true })

  -- List items
  hl("TodoItemNormal",      { fg = c.text,           bg = c.base })
  hl("TodoItemSelected",    { fg = c.text,           bg = c.overlay, bold = true })
  hl("TodoItemDone",        { fg = c.muted,          bg = c.base,    italic = true })

  -- Status indicators
  hl("TodoStatusPending",    { fg = c.subtle })
  hl("TodoStatusInProgress", { fg = c.gold,          bold = true })
  hl("TodoStatusDone",       { fg = c.foam })

  -- Priority indicators
  hl("TodoPriorityHigh",    { fg = c.love,           bold = true })
  hl("TodoPriorityMedium",  { fg = c.gold })
  hl("TodoPriorityLow",     { fg = c.muted })

  -- Detail panel
  hl("TodoDetailKey",       { fg = c.iris,           bold = true })
  hl("TodoDetailValue",     { fg = c.text })
  hl("TodoDetailDesc",      { fg = c.subtle,         italic = true })

  -- Scope badge (inverted — bg is the accent colour)
  hl("TodoScopeGlobal",     { fg = c.base,           bg = c.pine,    bold = true })
  hl("TodoScopeProject",    { fg = c.base,           bg = c.iris,    bold = true })

  -- Input prompt
  hl("TodoPrompt",          { fg = c.gold,           bold = true })
  hl("TodoPromptBorder",    { fg = c.gold,           bg = c.base })

  -- Vertical divider between panels
  hl("TodoDivider",         { fg = c.highlight_med,  bg = c.base })

  -- Empty state message
  hl("TodoEmpty",           { fg = c.muted,          italic = true })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- State shared across the current UI session
-- ─────────────────────────────────────────────────────────────────────────────
local state = {
  -- Window / buffer handles
  list_buf   = nil,
  list_win   = nil,
  detail_buf = nil,
  detail_win = nil,
  border_buf = nil,
  border_win = nil,

  -- Data
  todos  = {},
  cursor = 1,       -- 1-based index of selected item
  scope  = "project",
  config = nil,

  -- Dimensions computed on open
  total_width  = 0,
  total_height = 0,
  left_width   = 0,
  right_width  = 0,
  row          = 0,
  col          = 0,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Geometry helpers
-- ─────────────────────────────────────────────────────────────────────────────
local function compute_layout(config)
  local ui = vim.api.nvim_list_uis()[1]
  local w  = math.floor(ui.width  * config.ui.width)
  local h  = math.floor(ui.height * config.ui.height)
  local r  = math.floor((ui.height - h) / 2)
  local c  = math.floor((ui.width  - w) / 2)

  -- Left panel: split_ratio of total width; right panel gets the rest minus 1 (divider)
  local lw = math.max(20, math.floor(w * config.ui.split_ratio))
  local rw = w - lw - 1

  return { width = w, height = h, row = r, col = c, lw = lw, rw = rw }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Buffer helpers
-- ─────────────────────────────────────────────────────────────────────────────
local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe",   { buf = buf })
  vim.api.nvim_set_option_value("buftype",   "nofile", { buf = buf })
  vim.api.nvim_set_option_value("swapfile",  false,    { buf = buf })
  return buf
end

local function set_buf_lines(buf, lines)
  vim.api.nvim_set_option_value("modifiable", true,  { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Render the left (list) panel
-- ─────────────────────────────────────────────────────────────────────────────
local function render_list()
  local buf = state.list_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local w     = state.left_width
  local todos = state.todos
  local lines = {}
  local hls   = {}  -- { line_idx, col_start, col_end, hl_group }

  -- ── Header row ────────────────────────────────────────────────────────────
  local scope_label = state.scope == "global" and " ⊕ GLOBAL " or " ⊙ PROJECT "
  local scope_hl    = state.scope == "global" and "TodoScopeGlobal" or "TodoScopeProject"
  local count_str   = string.format(" %d items ", #todos)
  local pad_w       = math.max(0, w
    - vim.fn.strdisplaywidth(scope_label)
    - vim.fn.strdisplaywidth(count_str))

  lines[#lines + 1] = scope_label .. string.rep(" ", pad_w) .. count_str
  hls[#hls + 1] = { #lines - 1, 0, vim.fn.strdisplaywidth(scope_label), scope_hl }
  hls[#hls + 1] = { #lines - 1, 0, w, "TodoHeader" }

  -- ── Separator ─────────────────────────────────────────────────────────────
  lines[#lines + 1] = string.rep("─", w)
  hls[#hls + 1] = { #lines - 1, 0, w, "TodoSeparator" }

  -- ── Items or empty state ──────────────────────────────────────────────────
  if #todos == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = utils.center("  No TODOs yet", w)
    hls[#hls + 1] = { #lines - 1, 0, w, "TodoEmpty" }
    lines[#lines + 1] = utils.center("  Press [a] to add one", w)
    hls[#hls + 1] = { #lines - 1, 0, w, "TodoEmpty" }
  else
    for i, todo in ipairs(todos) do
      local s_icon, s_hl = utils.status_icon(todo.status)
      local p_icon, p_hl = utils.priority_icon(todo.priority)
      local is_sel       = (i == state.cursor)

      -- Layout: " <prio> <status>  <title padded> "
      local prefix   = string.format(" %s %s  ", p_icon, s_icon)
      local avail    = w - vim.fn.strdisplaywidth(prefix) - 1
      local title    = utils.truncate(todo.title or "", avail)
      local line_str = prefix .. utils.rpad(title, avail) .. " "

      lines[#lines + 1] = line_str

      local li     = #lines - 1
      local row_hl = is_sel and "TodoItemSelected"
        or (todo.status == "done" and "TodoItemDone" or "TodoItemNormal")

      hls[#hls + 1] = { li, 0, w, row_hl }
      hls[#hls + 1] = { li, 1, 2, p_hl }
      -- On selected rows keep status icon in the row highlight so it doesn't clash
      hls[#hls + 1] = { li, 3, 4, is_sel and row_hl or s_hl }
    end
  end

  -- ── Footer hint ───────────────────────────────────────────────────────────
  lines[#lines + 1] = string.rep("─", w)
  hls[#hls + 1] = { #lines - 1, 0, w, "TodoSeparator" }
  local hint = " a:add  d:del  e:edit  <CR>:toggle  v:preview  s:scope  ?:help "
  lines[#lines + 1] = utils.truncate(hint, w)
  hls[#hls + 1] = { #lines - 1, 0, w, "TodoFooter" }

  set_buf_lines(buf, lines)

  -- Apply highlight extmarks
  local ns = vim.api.nvim_create_namespace("todo_list_hl")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, hl in ipairs(hls) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl[4], hl[1], hl[2], hl[3])
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Render the right (detail) panel
-- ─────────────────────────────────────────────────────────────────────────────
local function render_detail()
  local buf = state.detail_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local w     = state.right_width
  local todo  = state.todos[state.cursor]
  local lines = {}
  local hls   = {}

  -- ── Panel title ───────────────────────────────────────────────────────────
  lines[#lines + 1] = utils.center("  Detail View ", w)
  hls[#hls + 1] = { #lines - 1, 0, w, "TodoHeader" }
  lines[#lines + 1] = string.rep("─", w)
  hls[#hls + 1] = { #lines - 1, 0, w, "TodoSeparator" }

  -- ── Empty selection ───────────────────────────────────────────────────────
  if not todo then
    lines[#lines + 1] = ""
    lines[#lines + 1] = utils.center("Select a TODO", w)
    hls[#hls + 1] = { #lines - 1, 0, w, "TodoEmpty" }
    lines[#lines + 1] = utils.center("to see details", w)
    hls[#hls + 1] = { #lines - 1, 0, w, "TodoEmpty" }

    set_buf_lines(buf, lines)
    local ns = vim.api.nvim_create_namespace("todo_detail_hl")
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, hl in ipairs(hls) do
      pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl[4], hl[1], hl[2], hl[3])
    end
    return
  end

  -- Helper: one key-value row with individual highlight spans
  local function field(key, value, val_hl)
    local k = utils.rpad(key .. ":", 12)
    lines[#lines + 1] = " " .. k .. " " .. (value or "—")
    local li = #lines - 1
    hls[#hls + 1] = { li, 1, 1 + #k,     "TodoDetailKey" }
    hls[#hls + 1] = { li, 1 + #k + 1, w, val_hl or "TodoDetailValue" }
  end

  -- ── Title (word-wrapped) ──────────────────────────────────────────────────
  lines[#lines + 1] = ""
  lines[#lines + 1] = " Title:"
  hls[#hls + 1] = { #lines - 1, 1, 7, "TodoDetailKey" }

  local title_words = vim.split(todo.title or "Untitled", " ")
  local cur_line    = "   "
  for _, word in ipairs(title_words) do
    if vim.fn.strdisplaywidth(cur_line .. word) > w - 2 then
      lines[#lines + 1] = cur_line
      hls[#hls + 1] = { #lines - 1, 0, w, "TodoDetailValue" }
      cur_line = "   " .. word .. " "
    else
      cur_line = cur_line .. word .. " "
    end
  end
  lines[#lines + 1] = cur_line
  hls[#hls + 1] = { #lines - 1, 0, w, "TodoDetailValue" }

  lines[#lines + 1] = ""

  -- ── Metadata fields ───────────────────────────────────────────────────────
  local s_icon, s_hl = utils.status_icon(todo.status)
  field("Status",   s_icon .. "  " .. (todo.status   or "pending"), s_hl)

  local p_icon, p_hl = utils.priority_icon(todo.priority)
  field("Priority", p_icon .. "  " .. (todo.priority or "low"),     p_hl)

  field("ID",      todo.id)
  field("Created", utils.fmt_time(todo.created_at))
  field("Updated", utils.fmt_time(todo.updated_at))

  -- ── Description — rendered as raw Markdown lines ─────────────────────────
  -- We intentionally write the raw Markdown text here.
  -- markview.nvim attaches to buffers with ft=markdown and renders them;
  -- the detail buffer gets ft=markdown set below so markview picks it up.
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.rep("─", w)
  hls[#hls + 1] = { #lines - 1, 0, w, "TodoSeparator" }

  local hint_suffix = todo.description and "  v:full preview" or ""
  lines[#lines + 1] = " Description:" .. hint_suffix
  hls[#hls + 1] = { #lines - 1, 1, 13, "TodoDetailKey" }
  if hint_suffix ~= "" then
    hls[#hls + 1] = { #lines - 1, 14, w, "TodoFooter" }
  end
  lines[#lines + 1] = ""

  if todo.description and todo.description ~= "" then
    -- Split stored multiline string back into individual lines
    local desc_lines = vim.split(todo.description, "\n", { plain = true })
    for _, dl in ipairs(desc_lines) do
      -- Indent each line by 2 spaces for visual padding inside the panel
      lines[#lines + 1] = "  " .. dl
      -- Don't add hl entries — markview will handle its own highlight extmarks
      -- on the ft=markdown buffer
    end
  else
    lines[#lines + 1] = "   (no description)"
    hls[#hls + 1] = { #lines - 1, 0, w, "TodoEmpty" }
  end

  set_buf_lines(buf, lines)

  -- Set filetype AFTER writing lines so markview attaches on the final content
  pcall(vim.api.nvim_set_option_value, "filetype", "markdown", { buf = buf })

  local ns = vim.api.nvim_create_namespace("todo_detail_hl")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, hl in ipairs(hls) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl[4], hl[1], hl[2], hl[3])
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Full render pass (list + detail + cursor sync)
-- ─────────────────────────────────────────────────────────────────────────────
local function render()
  render_list()
  render_detail()
  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    -- Header occupies lines 0-1, so item i is at line i+2
    pcall(vim.api.nvim_win_set_cursor, state.list_win, { state.cursor + 2, 0 })
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Reload todos from storage then re-render
-- ─────────────────────────────────────────────────────────────────────────────
local function reload()
  state.todos  = storage.load(state.scope)
  state.cursor = utils.clamp(state.cursor, 1, math.max(1, #state.todos))
  render()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Window creation
-- ─────────────────────────────────────────────────────────────────────────────
local function open_windows(config)
  local g = compute_layout(config)

  state.total_width  = g.width
  state.total_height = g.height
  state.left_width   = g.lw
  state.right_width  = g.rw

  -- ── Outer border window (decorative chrome) ───────────────────────────────
  state.border_buf = make_buf()
  state.border_win = vim.api.nvim_open_win(state.border_buf, false, {
    relative  = "editor",
    row       = g.row,
    col       = g.col,
    width     = g.width,
    height    = g.height,
    style     = "minimal",
    border    = config.ui.border,
    title     = " ✦ Todo Manager ",
    title_pos = "center",
    zindex    = 49,
  })
  vim.api.nvim_set_option_value("winhighlight",
    "Normal:TodoNormal,FloatBorder:TodoBorder,FloatTitle:TodoTitle",
    { win = state.border_win })

  -- ── Left (list) window — gets focus ───────────────────────────────────────
  state.list_buf = make_buf()
  state.list_win = vim.api.nvim_open_win(state.list_buf, true, {
    relative = "editor",
    row      = g.row + 1,
    col      = g.col + 1,
    width    = g.lw,
    height   = g.height - 2,
    style    = "minimal",
    border   = "none",
    zindex   = 50,
  })
  vim.api.nvim_set_option_value("winhighlight",
    "Normal:TodoNormal,CursorLine:TodoItemSelected",
    { win = state.list_win })
  vim.api.nvim_set_option_value("cursorline", false, { win = state.list_win })
  vim.api.nvim_set_option_value("scrolloff",  0,     { win = state.list_win })

  -- ── Right (detail) window ─────────────────────────────────────────────────
  state.detail_buf = make_buf()
  state.detail_win = vim.api.nvim_open_win(state.detail_buf, false, {
    relative = "editor",
    row      = g.row + 1,
    col      = g.col + g.lw + 2,  -- +1 border col, +1 divider col
    width    = g.rw,
    height   = g.height - 2,
    style    = "minimal",
    border   = "none",
    zindex   = 50,
  })
  vim.api.nvim_set_option_value("winhighlight",
    "Normal:TodoNormal",
    { win = state.detail_win })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Keymaps for the list buffer
-- ─────────────────────────────────────────────────────────────────────────────
local function setup_keymaps(config)
  local buf  = state.list_buf
  local pk   = config.panel_keymaps
  local opts = { noremap = true, silent = true, buffer = buf, nowait = true }

  -- Navigation
  vim.keymap.set("n", "j", function()
    if #state.todos == 0 then return end
    state.cursor = utils.clamp(state.cursor + 1, 1, #state.todos)
    render()
  end, opts)

  vim.keymap.set("n", "k", function()
    if #state.todos == 0 then return end
    state.cursor = utils.clamp(state.cursor - 1, 1, #state.todos)
    render()
  end, opts)

  vim.keymap.set("n", "G", function()
    state.cursor = math.max(1, #state.todos)
    render()
  end, opts)

  vim.keymap.set("n", "gg", function()
    state.cursor = 1
    render()
  end, opts)

  -- Toggle status
  vim.keymap.set("n", pk.toggle, function()
    local todo = state.todos[state.cursor]
    if not todo then return end
    storage.update(state.scope, todo.id, { status = utils.next_status(todo.status) })
    reload()
  end, opts)

  -- Cycle priority
  vim.keymap.set("n", pk.next_prio, function()
    local todo = state.todos[state.cursor]
    if not todo then return end
    storage.update(state.scope, todo.id, { priority = utils.next_priority(todo.priority) })
    reload()
  end, opts)

  -- Add
  vim.keymap.set("n", pk.add, function()
    M.quick_add(config)
  end, opts)

  -- Delete
  vim.keymap.set("n", pk.delete, function()
    local todo = state.todos[state.cursor]
    if not todo then return end
    M.confirm(
      'Delete "' .. utils.truncate(todo.title, 30) .. '"? [y/N]: ',
      function(ans)
        if ans:lower() == "y" then
          storage.delete(state.scope, todo.id)
          state.cursor = utils.clamp(state.cursor, 1, math.max(1, #state.todos - 1))
          reload()
        end
      end
    )
  end, opts)

  -- Edit
  vim.keymap.set("n", pk.edit, function()
    local todo = state.todos[state.cursor]
    if not todo then return end
    M.edit_todo(config, todo)
  end, opts)

  -- Switch scope
  vim.keymap.set("n", pk.scope, function()
    M.switch_scope(config)
  end, opts)

  -- Move item down in list
  vim.keymap.set("n", pk.move_down, function()
    if state.cursor < #state.todos then
      storage.reorder(state.scope, state.cursor, state.cursor + 1)
      state.cursor = state.cursor + 1
      reload()
    end
  end, opts)

  -- Move item up in list
  vim.keymap.set("n", pk.move_up, function()
    if state.cursor > 1 then
      storage.reorder(state.scope, state.cursor, state.cursor - 1)
      state.cursor = state.cursor - 1
      reload()
    end
  end, opts)

  -- Close
  vim.keymap.set("n", pk.close, M.close, opts)
  vim.keymap.set("n", "<Esc>",  M.close, opts)

  -- Help overlay
  vim.keymap.set("n", pk.help, function()
    M.show_help(config)
  end, opts)

  -- Full-screen Markdown preview of description
  vim.keymap.set("n", "v", function()
    local todo = state.todos[state.cursor]
    if not todo then return end
    editor.preview_description(todo.description)
  end, opts)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: Open the UI
-- ─────────────────────────────────────────────────────────────────────────────
function M.open(config)
  -- If already open just focus it
  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    vim.api.nvim_set_current_win(state.list_win)
    return
  end

  state.config = config
  state.scope  = config.default_scope or "project"

  -- Re-apply highlights with the user's color config on every open
  M.setup_highlights(config.colors)
  open_windows(config)
  setup_keymaps(config)

  -- Tear everything down cleanly when the list window is closed any other way
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(state.list_win),
    once     = true,
    callback = function() M.close() end,
  })

  reload()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: Close the UI
-- ─────────────────────────────────────────────────────────────────────────────
function M.close()
  for _, win in ipairs({ state.list_win, state.detail_win, state.border_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  state.list_win   = nil
  state.detail_win = nil
  state.border_win = nil
  state.list_buf   = nil
  state.detail_buf = nil
  state.border_buf = nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Input helpers (non-blocking via vim.ui.input)
-- ─────────────────────────────────────────────────────────────────────────────
function M.confirm(prompt, cb)
  vim.ui.input({ prompt = prompt }, function(ans)
    cb(ans or "")
  end)
end

--- Drive a sequential multi-field form through vim.ui.input
---@param fields table  list of { prompt, default, key }
---@param cb     function  called with table of { [key] = answer }
local function multi_input(fields, cb)
  local results = {}
  local function next_field(i)
    if i > #fields then
      cb(results)
      return
    end
    local f = fields[i]
    vim.ui.input({ prompt = f.prompt, default = f.default or "" }, function(val)
      if val == nil then return end  -- user cancelled with <C-c>
      results[f.key] = val
      next_field(i + 1)
    end)
  end
  next_field(1)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: Quick-add a TODO
-- Flow: title → priority (vim.ui.input) → description (Markdown editor)
-- ─────────────────────────────────────────────────────────────────────────────
function M.quick_add(config, prefill_title)
  state.config = config
  if not state.scope then
    state.scope = config.default_scope or "project"
  end

  -- Step 1 — title + priority via normal prompt fields
  local meta_fields = {
    { prompt = "Title: ",                      key = "title",    default = prefill_title or "" },
    { prompt = "Priority (low/medium/high): ", key = "priority", default = "medium" },
  }

  multi_input(meta_fields, function(res)
    if not res.title or res.title == "" then
      utils.warn("Title is required.")
      return
    end

    local priority = res.priority
    if priority ~= "low" and priority ~= "medium" and priority ~= "high" then
      priority = "medium"
    end

    -- Step 2 — open Markdown editor for description
    editor.open_editor({
      initial = "",
      on_save = function(desc_text)
        local todo = {
          id          = utils.new_id(),
          title       = res.title,
          description = desc_text ~= "" and desc_text or nil,
          status      = "pending",
          priority    = priority,
          created_at  = utils.now(),
          updated_at  = utils.now(),
        }

        storage.add(state.scope, todo)
        utils.info("TODO added: " .. todo.title)

        -- Refresh list if the main UI is open
        if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
          state.todos  = storage.load(state.scope)
          state.cursor = #state.todos
          render()
          vim.api.nvim_set_current_win(state.list_win)
        end
      end,
      on_cancel = function()
        utils.info("Add cancelled.")
        if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
          vim.api.nvim_set_current_win(state.list_win)
        end
      end,
    })
  end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: Edit an existing TODO
-- Flow: title + priority + status (vim.ui.input) → description (Markdown editor)
-- ─────────────────────────────────────────────────────────────────────────────
function M.edit_todo(config, todo)
  -- Step 1 — edit metadata fields
  local meta_fields = {
    { prompt = "Title: ",                             key = "title",    default = todo.title    or "" },
    { prompt = "Priority (low/medium/high): ",        key = "priority", default = todo.priority or "medium" },
    { prompt = "Status (pending/in_progress/done): ", key = "status",   default = todo.status   or "pending" },
  }

  multi_input(meta_fields, function(res)
    if not res.title or res.title == "" then
      utils.warn("Title cannot be empty.")
      return
    end

    local priority = res.priority
    if priority ~= "low" and priority ~= "medium" and priority ~= "high" then
      priority = todo.priority
    end

    local status = res.status
    if status ~= "pending" and status ~= "in_progress" and status ~= "done" then
      status = todo.status
    end

    -- Step 2 — open Markdown editor pre-filled with existing description
    editor.open_editor({
      initial = todo.description or "",
      on_save = function(desc_text)
        storage.update(state.scope, todo.id, {
          title       = res.title,
          description = desc_text ~= "" and desc_text or nil,
          priority    = priority,
          status      = status,
        })

        utils.info("TODO updated.")
        if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
          reload()
          vim.api.nvim_set_current_win(state.list_win)
        end
      end,
      on_cancel = function()
        -- Metadata changes are still committed; only description edit was cancelled.
        -- Save meta without touching description.
        storage.update(state.scope, todo.id, {
          title    = res.title,
          priority = priority,
          status   = status,
        })
        utils.info("Description edit cancelled — metadata saved.")
        if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
          reload()
          vim.api.nvim_set_current_win(state.list_win)
        end
      end,
    })
  end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: Quick-toggle the selected TODO's status (works without the UI open)
-- ─────────────────────────────────────────────────────────────────────────────
function M.quick_toggle(config)
  state.config = state.config or config
  local scope  = state.scope or config.default_scope or "project"
  local todos  = storage.load(scope)

  if #todos == 0 then
    utils.warn("No TODOs found in scope: " .. scope)
    return
  end

  local todo       = todos[state.cursor] or todos[1]
  local new_status = utils.next_status(todo.status)
  storage.update(scope, todo.id, { status = new_status })
  utils.info(string.format("'%s' → %s", utils.truncate(todo.title, 30), new_status))

  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    reload()
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: Switch scope (global ↔ project) or set explicitly
-- ─────────────────────────────────────────────────────────────────────────────
function M.switch_scope(config, explicit_scope)
  state.config = state.config or config

  if explicit_scope then
    state.scope = explicit_scope
  else
    state.scope = state.scope == "project" and "global" or "project"
  end

  state.cursor = 1
  utils.info("Scope → " .. state.scope)

  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    reload()
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: Show help overlay
-- ─────────────────────────────────────────────────────────────────────────────
function M.show_help(config)
  local pk    = config.panel_keymaps
  local lines = {
    "",
    utils.center("  ✦ Keybindings ", 40),
    string.rep("─", 40),
    "",
    string.format("  %-8s  Navigate up / down",  "j / k"),
    string.format("  %-8s  Add new TODO",         pk.add),
    string.format("  %-8s  Delete TODO",          pk.delete),
    string.format("  %-8s  Edit TODO",            pk.edit),
    string.format("  %-8s  Toggle status",        pk.toggle),
    string.format("  %-8s  Preview description",   "v"),
    string.format("  %-8s  Cycle priority",       pk.next_prio),
    string.format("  %-8s  Move item up",         pk.move_up),
    string.format("  %-8s  Move item down",       pk.move_down),
    string.format("  %-8s  Switch scope",         pk.scope),
    string.format("  %-8s  Close",                pk.close),
    "",
    string.rep("─", 40),
    utils.center("  Press any key to close ", 40),
    "",
  }

  local buf = make_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local ui   = vim.api.nvim_list_uis()[1]
  local w, h = 42, #lines + 2
  local win  = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    row       = math.floor((ui.height - h) / 2),
    col       = math.floor((ui.width  - w) / 2),
    width     = w,
    height    = h,
    style     = "minimal",
    border    = "rounded",
    title     = " Help ",
    title_pos = "center",
    zindex    = 100,
  })
  vim.api.nvim_set_option_value("winhighlight",
    "Normal:TodoNormal,FloatBorder:TodoBorder,FloatTitle:TodoTitle",
    { win = win })

  -- Highlights
  local ns = vim.api.nvim_create_namespace("todo_help_hl")
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, "TodoHeader", 2, 0, -1)
  for i = 4, #lines - 3 do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, "TodoDetailValue", i, 0, -1)
  end

  -- Any of these keys dismisses the overlay and returns focus
  local function close_help()
    pcall(vim.api.nvim_win_close, win, true)
    if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
      vim.api.nvim_set_current_win(state.list_win)
    end
  end

  for _, key in ipairs({ "q", "<Esc>", "<CR>", "?", "<Space>" }) do
    vim.keymap.set("n", key, close_help, { buffer = buf, noremap = true, silent = true })
  end
end

return M
