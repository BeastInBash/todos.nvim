--- todo-nvim/editor.lua
--- Floating Markdown editor for TODO descriptions
---
--- Opens a proper editable buffer with:
---   • filetype=markdown  (triggers markview.nvim automatically)
---   • Full insert/normal mode editing
---   • <leader>w or :w  to save and close
---   • <Esc><Esc> / q (normal mode)  to cancel
---
--- markview.nvim attaches itself to any buffer whose filetype is "markdown",
--- so no explicit integration code is needed — it just works.

local M = {}

local utils = require("todo-nvim.utils")

-- ─────────────────────────────────────────────────────────────────────────────
-- Geometry: editor takes up most of the screen, centred
-- ─────────────────────────────────────────────────────────────────────────────
local function editor_layout()
    local ui = vim.api.nvim_list_uis()[1]
    local w  = math.floor(ui.width * 0.72)
    local h  = math.floor(ui.height * 0.65)
    local r  = math.floor((ui.height - h) / 2)
    local c  = math.floor((ui.width - w) / 2)
    return { width = w, height = h, row = r, col = c }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: open_editor
--
-- @param opts table
--   • initial   string|nil   existing description content (may be multiline)
--   • on_save   function(text: string)  called with final content on save
--   • on_cancel function|nil            called when user cancels (no-op default)
-- ─────────────────────────────────────────────────────────────────────────────
function M.open_editor(opts)
    opts            = opts or {}
    local initial   = opts.initial or ""
    local on_save   = opts.on_save or function() end
    local on_cancel = opts.on_cancel or function() end

    local g         = editor_layout()

    -- ── Create an editable buffer ─────────────────────────────────────────────
    local buf       = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

    -- Seed with existing content (split on literal \n stored in JSON)
    local initial_lines = vim.split(initial, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)

    -- Mark buffer unmodified so the "unsaved changes" warning doesn't fire
    vim.api.nvim_set_option_value("modified", false, { buf = buf })

    -- ── Open the floating window ──────────────────────────────────────────────
    local win = vim.api.nvim_open_win(buf, true, {
        relative  = "editor",
        row       = g.row,
        col       = g.col,
        width     = g.width,
        height    = g.height,
        style     = "minimal",
        border    = "rounded",
        title     = " ✎ Description — Markdown  │  <leader>w save  │  q cancel ",
        title_pos = "center",
        zindex    = 60,
    })

    -- Apply visual options on the window
    vim.api.nvim_set_option_value("winhighlight",
        "Normal:TodoNormal,FloatBorder:TodoBorder,FloatTitle:TodoTitle",
        { win = win })
    vim.api.nvim_set_option_value("wrap", true, { win = win })
    vim.api.nvim_set_option_value("linebreak", true, { win = win })
    vim.api.nvim_set_option_value("breakindent", true, { win = win })
    vim.api.nvim_set_option_value("number", true, { win = win })
    vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
    vim.api.nvim_set_option_value("scrolloff", 3, { win = win })

    -- Place cursor at end of content
    local line_count = vim.api.nvim_buf_line_count(buf)
    pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })

    -- ── Helpers ───────────────────────────────────────────────────────────────
    local saved = false -- guard against double-firing

    local function do_save()
        if saved then return end
        saved = true
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        -- Trim trailing blank lines
        while #lines > 0 and lines[#lines]:match("^%s*$") do
            lines[#lines] = nil
        end
        local text = table.concat(lines, "\n")
        pcall(vim.api.nvim_win_close, win, true)
        on_save(text)
    end

    local function do_cancel()
        if saved then return end
        saved = true
        pcall(vim.api.nvim_win_close, win, true)
        on_cancel()
    end

    -- ── Keymaps (buffer-local) ─────────────────────────────────────────────────
    local map = function(mode, lhs, fn, desc)
        vim.keymap.set(mode, lhs, fn, {
            buffer  = buf,
            noremap = true,
            silent  = true,
            desc    = desc,
        })
    end

    -- Save: <leader>w in normal or insert mode
    map("n", "<leader>w", do_save, "Save description")
    map("i", "<leader>w", function()
        vim.cmd("stopinsert")
        do_save()
    end, "Save description")

    -- Also support :w inside the buffer (autocmd on BufWriteCmd)
    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer   = buf,
        once     = true,
        callback = function()
            do_save()
            return true -- suppress "E382: Cannot write, 'buftype' option is set"
        end,
    })

    -- Cancel: q in normal mode, or double-Esc
    map("n", "q", do_cancel, "Cancel / discard")
    map("n", "<Esc>", do_cancel, "Cancel / discard")
    map("i", "<Esc><Esc>", function()
        vim.cmd("stopinsert")
        do_cancel()
    end, "Cancel / discard")

    -- Convenience: Ctrl+s saves from insert mode (muscle memory)
    map("i", "<C-s>", function()
        vim.cmd("stopinsert")
        do_save()
    end, "Save description")
    map("n", "<C-s>", do_save, "Save description")

    -- ── Auto-close if window is closed by other means (e.g. :q) ──────────────
    vim.api.nvim_create_autocmd("WinClosed", {
        pattern  = tostring(win),
        once     = true,
        callback = function()
            if not saved then
                saved = true
                on_cancel()
            end
        end,
    })

    -- ── Enter insert mode at the end so user can type immediately ─────────────
    -- Schedule so markview has time to attach first
    vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
            vim.cmd("startinsert!")
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: preview_description
--
-- Read-only floating preview of a Markdown description.
-- Used by the detail panel when the user presses a dedicated key.
-- markview renders it automatically because ft=markdown.
--
-- @param description string   raw Markdown text
-- ─────────────────────────────────────────────────────────────────────────────
function M.preview_description(description)
    if not description or description == "" then
        utils.info("No description to preview.")
        return
    end

    local g   = editor_layout()
    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

    local lines = vim.split(description, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

    local win = vim.api.nvim_open_win(buf, true, {
        relative  = "editor",
        row       = g.row,
        col       = g.col,
        width     = g.width,
        height    = g.height,
        style     = "minimal",
        border    = "rounded",
        title     = " 👁 Description Preview — q / <Esc> to close ",
        title_pos = "center",
        zindex    = 60,
    })

    vim.api.nvim_set_option_value("winhighlight",
        "Normal:TodoNormal,FloatBorder:TodoBorder,FloatTitle:TodoTitle",
        { win = win })
    vim.api.nvim_set_option_value("wrap", true, { win = win })
    vim.api.nvim_set_option_value("linebreak", true, { win = win })
    vim.api.nvim_set_option_value("number", false, { win = win })
    vim.api.nvim_set_option_value("signcolumn", "no", { win = win })

    local function close()
        pcall(vim.api.nvim_win_close, win, true)
    end

    for _, key in ipairs({ "q", "<Esc>", "<CR>" }) do
        vim.keymap.set("n", key, close, { buffer = buf, noremap = true, silent = true })
    end
end

return M
