--- todo-nvim/storage.lua
--- Handles all persistent storage operations (JSON-based)
--- Supports both global and project-scoped TODO files

local M = {}
local utils = require("todo-nvim.utils")

-- Cached config reference
local _config = nil

--- Initialize storage — create directories and seed empty files if needed
---@param config table Plugin configuration
function M.init(config)
  _config = config
  utils.ensure_dir(vim.fn.fnamemodify(config.storage.global_path, ":h"))
  -- Project dir is created lazily on first write (project root may not be known at init)
end

--- Returns the absolute path for the global TODO file
---@return string
function M.global_path()
  return _config.storage.global_path
end

--- Returns the absolute path for the current project's TODO file
--- Returns nil if no project root is detected
---@return string|nil
function M.project_path()
  local root = utils.find_project_root()
  if not root then return nil end
  return root .. "/" .. _config.storage.project_filename
end

--- Read and parse a JSON todo file
--- Returns an empty table on missing / corrupted file
---@param path string Absolute path to JSON file
---@return table List of TODO items
function M.read(path)
  if not path then return {} end
  if vim.fn.filereadable(path) == 0 then return {} end

  local ok, content = pcall(vim.fn.readfile, path)
  if not ok or not content or #content == 0 then return {} end

  local raw = table.concat(content, "\n")
  if raw:match("^%s*$") then return {} end

  local ok2, data = pcall(vim.fn.json_decode, raw)
  if not ok2 or type(data) ~= "table" then
    utils.warn("Corrupted TODO file at " .. path .. " — starting fresh.")
    return {}
  end

  -- Validate each item has required fields; drop malformed ones
  local valid = {}
  for _, item in ipairs(data) do
    if type(item) == "table" and item.id and item.title then
      valid[#valid + 1] = item
    end
  end
  return valid
end

--- Write a list of TODOs to a JSON file atomically (write to tmp, rename)
---@param path string Absolute path to JSON file
---@param todos table List of TODO items
---@return boolean success
function M.write(path, todos)
  if not path then return false end

  utils.ensure_dir(vim.fn.fnamemodify(path, ":h"))

  local ok, encoded = pcall(vim.fn.json_encode, todos)
  if not ok then
    utils.warn("Failed to encode TODOs to JSON.")
    return false
  end

  -- Pretty-print via Lua (vim.fn.json_encode produces compact JSON)
  local pretty = utils.json_pretty(todos)
  local tmp = path .. ".tmp"

  local ok2 = pcall(vim.fn.writefile, vim.split(pretty, "\n"), tmp)
  if not ok2 then
    utils.warn("Failed to write TODO file: " .. path)
    return false
  end

  -- Atomic rename
  local ok3 = os.rename(tmp, path)
  if not ok3 then
    -- Fallback: direct write
    pcall(vim.fn.writefile, vim.split(pretty, "\n"), path)
  end

  return true
end

--- Load todos for a given scope
---@param scope string "global" | "project"
---@return table, string|nil  todos list, resolved path
function M.load(scope)
  local path = scope == "global" and M.global_path() or M.project_path()
  return M.read(path), path
end

--- Save todos for a given scope
---@param scope string "global" | "project"
---@param todos table List of TODO items
---@return boolean
function M.save(scope, todos)
  local path = scope == "global" and M.global_path() or M.project_path()
  return M.write(path, todos)
end

--- Add a todo item to the given scope
---@param scope string
---@param todo table
---@return boolean
function M.add(scope, todo)
  local todos = M.load(scope)
  todos[#todos + 1] = todo
  return M.save(scope, todos)
end

--- Update a todo item by id
---@param scope string
---@param id string
---@param updates table Fields to update
---@return boolean
function M.update(scope, id, updates)
  local todos = M.load(scope)
  local found = false
  for i, item in ipairs(todos) do
    if item.id == id then
      todos[i] = vim.tbl_extend("force", item, updates)
      todos[i].updated_at = utils.now()
      found = true
      break
    end
  end
  if not found then return false end
  return M.save(scope, todos)
end

--- Delete a todo item by id
---@param scope string
---@param id string
---@return boolean
function M.delete(scope, id)
  local todos = M.load(scope)
  local new_todos = {}
  for _, item in ipairs(todos) do
    if item.id ~= id then
      new_todos[#new_todos + 1] = item
    end
  end
  if #new_todos == #todos then return false end -- not found
  return M.save(scope, new_todos)
end

--- Reorder todos (for move up/down)
---@param scope string
---@param from_idx integer
---@param to_idx integer
---@return boolean
function M.reorder(scope, from_idx, to_idx)
  local todos = M.load(scope)
  if from_idx < 1 or from_idx > #todos then return false end
  if to_idx < 1 or to_idx > #todos then return false end

  local item = table.remove(todos, from_idx)
  table.insert(todos, to_idx, item)
  return M.save(scope, todos)
end

return M
