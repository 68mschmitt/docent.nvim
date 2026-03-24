--- Git operations for branch management during reviews.
--- Handles stashing changes, checking out PR branches, and restoring state.
local config = require("docent.config")

local M = {}

---@class docent.GitState
---@field original_branch string|nil Branch the user was on before the review
---@field did_stash boolean Whether we stashed changes
---@field pr_branch string|nil The PR branch we checked out
local state = {
  original_branch = nil,
  did_stash = false,
  pr_branch = nil,
}

---Run a git command asynchronously.
---@param args string[] Git subcommand and arguments (without "git")
---@param callback fun(stdout: string, stderr: string, code: number)
local function run_git(args, callback)
  local cmd = { "git" }
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end

  local stdout_chunks = {}
  local stderr_chunks = {}

  vim.fn.jobstart(cmd, {
    cwd = vim.fn.getcwd(),
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_chunks, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_chunks, line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        callback(table.concat(stdout_chunks, "\n"), table.concat(stderr_chunks, "\n"), code)
      end)
    end,
  })
end

---Get the current branch name synchronously (fast, local operation).
---@return string|nil
local function current_branch()
  local result = vim.fn.systemlist({ "git", "rev-parse", "--abbrev-ref", "HEAD" })
  if vim.v.shell_error == 0 and result[1] then
    return vim.trim(result[1])
  end
  return nil
end

---Check if the working tree has uncommitted changes (staged or unstaged).
---@return boolean
local function has_changes()
  vim.fn.system({ "git", "status", "--porcelain" })
  local result = vim.fn.systemlist({ "git", "status", "--porcelain" })
  return #result > 0
end

---Stash current changes if any, record the original branch, then
---checkout the PR branch using `gh pr checkout` and pull latest.
---@param pr_number number PR number
---@param callback fun(err: string|nil)
function M.checkout_pr(pr_number, callback)
  local gh = config.get().gh_cmd

  -- Record original branch
  state.original_branch = current_branch()
  state.did_stash = false
  state.pr_branch = nil

  -- Check for uncommitted changes
  if has_changes() then
    state.did_stash = true
    run_git({ "stash", "push", "-m", "docent: auto-stash before PR review" }, function(_, stderr, code)
      if code ~= 0 then
        callback("Failed to stash changes: " .. stderr)
        return
      end
      M._do_checkout(gh, pr_number, callback)
    end)
  else
    M._do_checkout(gh, pr_number, callback)
  end
end

---Internal: run `gh pr checkout` then `git pull`.
---@param gh string Path to gh binary
---@param pr_number number
---@param callback fun(err: string|nil)
function M._do_checkout(gh, pr_number, callback)
  -- gh pr checkout handles fetching the remote and creating/switching to the branch
  local checkout_cmd = { gh, "pr", "checkout", tostring(pr_number) }
  local stdout_chunks = {}
  local stderr_chunks = {}

  vim.fn.jobstart(checkout_cmd, {
    cwd = vim.fn.getcwd(),
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then table.insert(stdout_chunks, line) end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then table.insert(stderr_chunks, line) end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          local stderr = table.concat(stderr_chunks, "\n")
          callback("Failed to checkout PR: " .. stderr)
          return
        end

        -- Record the branch we landed on
        state.pr_branch = current_branch()

        -- Pull latest
        run_git({ "pull", "--ff-only" }, function(_, pull_stderr, pull_code)
          -- ff-only pull failing is non-fatal (branch may already be up to date,
          -- or there may be divergence -- either way the checkout succeeded)
          if pull_code ~= 0 then
            -- Try a plain pull as fallback
            run_git({ "pull" }, function(_, _, _)
              callback(nil)
            end)
          else
            callback(nil)
          end
        end)
      end)
    end,
  })
end

---Restore the original branch and pop the stash if we created one.
---@param callback fun(err: string|nil)
function M.restore(callback)
  if not state.original_branch then
    callback(nil)
    return
  end

  local branch = state.original_branch

  run_git({ "checkout", branch }, function(_, stderr, code)
    if code ~= 0 then
      callback("Failed to restore branch '" .. branch .. "': " .. stderr)
      return
    end

    if state.did_stash then
      run_git({ "stash", "pop" }, function(_, pop_stderr, pop_code)
        -- Reset state regardless of pop result
        state.original_branch = nil
        state.did_stash = false
        state.pr_branch = nil

        if pop_code ~= 0 then
          callback("Branch restored but failed to pop stash: " .. pop_stderr)
        else
          callback(nil)
        end
      end)
    else
      state.original_branch = nil
      state.did_stash = false
      state.pr_branch = nil
      callback(nil)
    end
  end)
end

---Get the current git state (for display in stages).
---@return docent.GitState
function M.get_state()
  return state
end

---Reset state without performing git operations (for cleanup on error paths).
function M.reset()
  state = {
    original_branch = nil,
    did_stash = false,
    pr_branch = nil,
  }
end

return M
