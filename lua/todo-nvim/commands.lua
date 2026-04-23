--- todo-nvim/commands.lua
--- Registers all :Todo* user commands

local M = {}

--- Register all plugin commands
---@param config table Plugin configuration
function M.register(config)
  -- :TodoOpen — open the full UI
  vim.api.nvim_create_user_command("TodoOpen", function()
    require("todo-nvim.ui").open(config)
  end, { desc = "Open Todo manager UI" })

  -- :TodoAdd [title] — quick-add a todo, optionally with a title arg
  vim.api.nvim_create_user_command("TodoAdd", function(opts)
    local title = opts.args ~= "" and opts.args or nil
    require("todo-nvim.ui").quick_add(config, title)
  end, {
    nargs = "?",
    desc  = "Quick-add a TODO item",
  })

  -- :TodoToggle — toggle the status of the most-recent / selected todo
  vim.api.nvim_create_user_command("TodoToggle", function()
    require("todo-nvim.ui").quick_toggle(config)
  end, { desc = "Toggle the status of the last selected TODO" })

  -- :TodoScope [global|project] — switch scope or toggle if no arg
  vim.api.nvim_create_user_command("TodoScope", function(opts)
    local scope = opts.args ~= "" and opts.args or nil
    require("todo-nvim.ui").switch_scope(config, scope)
  end, {
    nargs = "?",
    complete = function()
      return { "global", "project" }
    end,
    desc = "Switch TODO scope (global / project)",
  })
end

return M
