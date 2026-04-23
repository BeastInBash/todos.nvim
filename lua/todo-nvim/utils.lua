--- todo-nvim/utils.lua
--- Shared utility functions used across all modules

local M = {}

--- Display a warning notification
---@param msg string
function M.warn(msg)
  vim.notify("[todo-nvim] " .. msg, vim.log.levels.WARN)
end

--- Display an info notification
---@param msg string
function M.info(msg)
  vim.notify("[todo-nvim] " .. msg, vim.log.levels.INFO)
end

--- Display an error notification
---@param msg string
function M.err(msg)
  vim.notify("[todo-nvim] " .. msg, vim.log.levels.ERROR)
end

--- Get current ISO-8601-like timestamp
---@return string
function M.now()
  return os.date("%Y-%m-%dT%H:%M:%S")
end

--- Generate a short unique ID (8 hex chars)
---@return string
function M.new_id()
  math.randomseed(os.time() + math.random(1, 99999))
  return string.format("%08x", math.random(0, 0xFFFFFFFF))
end

--- Ensure a directory exists, creating it recursively if needed
---@param path string
function M.ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
end

--- Find the project root by looking for marker files/dirs
---@return string|nil  Absolute path to project root
function M.find_project_root()
  local markers = { ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml", ".nvim" }
  local cwd = vim.fn.getcwd()

  local path = cwd
  for _ = 1, 20 do -- max 20 levels up
    for _, marker in ipairs(markers) do
      if vim.fn.filereadable(path .. "/" .. marker) == 1
        or vim.fn.isdirectory(path .. "/" .. marker) == 1
      then
        return path
      end
    end
    local parent = vim.fn.fnamemodify(path, ":h")
    if parent == path then break end -- filesystem root
    path = parent
  end

  -- Fall back to cwd if no marker found
  return cwd
end

--- Clamp a number between min and max
---@param n number
---@param min number
---@param max number
---@return number
function M.clamp(n, min, max)
  return math.min(math.max(n, min), max)
end

--- Truncate a string to max_len, appending "…" if needed
---@param s string
---@param max_len integer
---@return string
function M.truncate(s, max_len)
  if #s <= max_len then return s end
  return s:sub(1, max_len - 1) .. "…"
end

--- Pad a string on the right to a given width
---@param s string
---@param width integer
---@return string
function M.rpad(s, width)
  local len = vim.fn.strdisplaywidth(s)
  if len >= width then return s end
  return s .. string.rep(" ", width - len)
end

--- Center a string within a given width
---@param s string
---@param width integer
---@return string
function M.center(s, width)
  local len = vim.fn.strdisplaywidth(s)
  if len >= width then return s end
  local pad = math.floor((width - len) / 2)
  return string.rep(" ", pad) .. s
end

--- Pretty-print a Lua table to JSON (indented 2 spaces)
--- Falls back to vim.fn.json_encode on error
---@param tbl table
---@return string
function M.json_pretty(tbl)
  -- Use a recursive Lua implementation to avoid external dependencies
  local function serialize(val, indent)
    local t = type(val)
    if t == "nil" then
      return "null"
    elseif t == "boolean" then
      return tostring(val)
    elseif t == "number" then
      return tostring(val)
    elseif t == "string" then
      -- Escape special characters
      local s = val
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\n', '\\n')
        :gsub('\r', '\\r')
        :gsub('\t', '\\t')
      return '"' .. s .. '"'
    elseif t == "table" then
      -- Detect array vs object
      local is_array = #val > 0
      if is_array then
        local items = {}
        for _, v in ipairs(val) do
          items[#items + 1] = string.rep("  ", indent + 1) .. serialize(v, indent + 1)
        end
        if #items == 0 then return "[]" end
        return "[\n" .. table.concat(items, ",\n") .. "\n" .. string.rep("  ", indent) .. "]"
      else
        local keys = {}
        for k in pairs(val) do keys[#keys + 1] = k end
        table.sort(keys)
        local items = {}
        for _, k in ipairs(keys) do
          local v = val[k]
          if v ~= nil then
            items[#items + 1] = string.rep("  ", indent + 1)
              .. '"' .. k .. '": '
              .. serialize(v, indent + 1)
          end
        end
        if #items == 0 then return "{}" end
        return "{\n" .. table.concat(items, ",\n") .. "\n" .. string.rep("  ", indent) .. "}"
      end
    end
    return "null"
  end

  local ok, result = pcall(serialize, tbl, 0)
  if ok then return result end
  -- Fallback
  local ok2, enc = pcall(vim.fn.json_encode, tbl)
  return ok2 and enc or "[]"
end

--- Map a status string to a display icon
---@param status string
---@return string icon, string hl_group
function M.status_icon(status)
  if status == "done"        then return "✓", "TodoStatusDone" end
  if status == "in_progress" then return "◐", "TodoStatusInProgress" end
  return "○", "TodoStatusPending"
end

--- Map a priority string to a display icon + color
---@param priority string
---@return string icon, string hl_group
function M.priority_icon(priority)
  if priority == "high"   then return "▲", "TodoPriorityHigh" end
  if priority == "medium" then return "●", "TodoPriorityMedium" end
  return "▽", "TodoPriorityLow"
end

--- Cycle status: pending → in_progress → done → pending
---@param status string
---@return string
function M.next_status(status)
  if status == "pending"     then return "in_progress" end
  if status == "in_progress" then return "done" end
  return "pending"
end

--- Cycle priority: low → medium → high → low
---@param priority string
---@return string
function M.next_priority(priority)
  if priority == "low"    then return "medium" end
  if priority == "medium" then return "high" end
  return "low"
end

--- Format a timestamp for display
---@param ts string ISO timestamp
---@return string
function M.fmt_time(ts)
  if not ts then return "—" end
  -- Extract date portion
  return ts:match("^(%d+%-%d+%-%d+)") or ts
end

return M
