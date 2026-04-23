--- todo-nvim/init.lua
--- Main entry point for the todo-nvim plugin
--- Orchestrates all modules and exposes the public API

local M = {}

-- Default configuration
M.config = {
  default_scope = "project", -- "project" | "global"
  storage = {
    global_path = vim.fn.stdpath("data") .. "/todo/global.json",
    project_filename = ".nvim/todo.json",
  },
  ui = {
    width = 0.8,    -- fraction of editor width
    height = 0.8,   -- fraction of editor height
    border = "rounded",
    split_ratio = 0.4, -- left panel width ratio
  },
  keymaps = {
    open     = "<leader>td",
    add      = "<leader>ta",
    toggle   = "<leader>tt",
    scope    = "<leader>ts",
  },
  -- Panel-level keymaps (inside the floating window)
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
}

--- Setup function — call this from your Neovim config
---@param user_config table|nil Optional config overrides
function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

  -- Ensure storage directories exist
  local storage = require("todo-nvim.storage")
  storage.init(M.config)

  -- Register commands
  local commands = require("todo-nvim.commands")
  commands.register(M.config)

  -- Register global keymaps
  local keymaps = M.config.keymaps
  local opts = { noremap = true, silent = true }

  vim.keymap.set("n", keymaps.open, function()
    require("todo-nvim.ui").open(M.config)
  end, vim.tbl_extend("force", opts, { desc = "Todo: Open UI" }))

  vim.keymap.set("n", keymaps.add, function()
    require("todo-nvim.ui").quick_add(M.config)
  end, vim.tbl_extend("force", opts, { desc = "Todo: Quick Add" }))

  vim.keymap.set("n", keymaps.toggle, function()
    require("todo-nvim.ui").quick_toggle(M.config)
  end, vim.tbl_extend("force", opts, { desc = "Todo: Toggle Status" }))

  vim.keymap.set("n", keymaps.scope, function()
    require("todo-nvim.ui").switch_scope(M.config)
  end, vim.tbl_extend("force", opts, { desc = "Todo: Switch Scope" }))

  -- Define highlight groups
  require("todo-nvim.ui").setup_highlights()
end

return M
