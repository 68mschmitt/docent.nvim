--- Storage module for saving and loading reviews to/from disk.
local config = require("docent.config")

local M = {}

---Ensure the data directory exists.
---@return string path
local function ensure_dir()
  local dir = config.get().data_dir
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  return dir
end

---Generate a filename for a review based on PR info.
---@param data table Serialized session data
---@return string filename
local function make_filename(data)
  local pr = data.pr_info
  local name
  if pr then
    name = string.format("%s_%s_%d", pr.owner, pr.repo, pr.number)
  else
    name = "review"
  end
  -- Add a timestamp to avoid collisions
  local ts = os.date("%Y%m%d_%H%M%S")
  return name .. "_" .. ts .. ".json"
end

---Save a serialized review to disk.
---@param data table Serialized session data from session.serialize()
---@return string|nil path Path the file was written to
---@return string|nil err Error message if failed
function M.save(data)
  local dir = ensure_dir()
  local filename = make_filename(data)
  local path = dir .. "/" .. filename

  local json = vim.json.encode(data)
  local file, err = io.open(path, "w")
  if not file then
    return nil, "Failed to write " .. path .. ": " .. (err or "unknown error")
  end
  file:write(json)
  file:close()
  return path, nil
end

---Load a review from a file path.
---@param path string Full path to the JSON file
---@return table|nil data The deserialized data
---@return string|nil err Error message if failed
function M.load(path)
  local file, err = io.open(path, "r")
  if not file then
    return nil, "Failed to read " .. path .. ": " .. (err or "unknown error")
  end
  local content = file:read("*a")
  file:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil, "Failed to parse " .. path .. ": " .. tostring(data)
  end
  return data, nil
end

---Load the most recent saved review for the current repo.
---@return table|nil data
function M.load_latest()
  local files = M.list_saved()
  if #files == 0 then return nil end
  -- Files are sorted newest first by list_saved
  local data, err = M.load(files[1])
  if err then return nil end
  return data
end

---List all saved review files, newest first.
---@return string[] Full paths to saved review JSON files
function M.list_saved()
  local dir = config.get().data_dir
  if vim.fn.isdirectory(dir) == 0 then
    return {}
  end

  local files = vim.fn.glob(dir .. "/*.json", false, true)
  -- Sort by modification time, newest first
  table.sort(files, function(a, b)
    return vim.fn.getftime(a) > vim.fn.getftime(b)
  end)
  return files
end

return M
