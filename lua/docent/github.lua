--- GitHub integration via gh CLI.
--- Handles fetching PR data, diffs, posting comments, and review actions.
local config = require("docent.config")

local M = {}

---@class docent.PRInfo
---@field owner string Repository owner
---@field repo string Repository name
---@field number number PR number
---@field title string PR title
---@field author string PR author
---@field base string Base branch
---@field head string Head branch
---@field url string PR URL
---@field state string PR state (OPEN, CLOSED, MERGED)
---@field additions number Lines added
---@field deletions number Lines deleted
---@field changed_files number Number of changed files

---Run a gh command asynchronously and collect stdout/stderr.
---Callback is invoked exactly once from on_exit.
---@param cmd string[]
---@param callback fun(stdout: string, stderr: string, code: number)
local function run_gh(cmd, callback)
  local stdout_chunks = {}
  local stderr_chunks = {}

  vim.fn.jobstart(cmd, {
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
        local stdout = table.concat(stdout_chunks, "\n")
        local stderr = table.concat(stderr_chunks, "\n")
        callback(stdout, stderr, code)
      end)
    end,
  })
end

---Parse a PR reference into owner, repo, and number.
---Accepts: #123, 123, owner/repo#123, https://github.com/owner/repo/pull/123
---For bare numbers (#123), fetches repo info asynchronously.
---@param pr_ref string
---@param callback fun(owner: string|nil, repo: string|nil, number: number|nil, err: string|nil)
function M.parse_pr_ref(pr_ref, callback)
  -- Full URL: https://github.com/owner/repo/pull/123
  local url_owner, url_repo, url_num = pr_ref:match("github%.com/([^/]+)/([^/]+)/pull/(%d+)")
  if url_owner then
    callback(url_owner, url_repo, tonumber(url_num), nil)
    return
  end

  -- owner/repo#123
  local ref_owner, ref_repo, ref_num = pr_ref:match("^([^/]+)/([^#]+)#(%d+)$")
  if ref_owner then
    callback(ref_owner, ref_repo, tonumber(ref_num), nil)
    return
  end

  -- #123 or 123 (needs repo context from gh -- async)
  local num = pr_ref:match("^#?(%d+)$")
  if num then
    local gh = config.get().gh_cmd
    run_gh({ gh, "repo", "view", "--json", "owner,name" }, function(stdout, stderr, code)
      if code ~= 0 then
        callback(nil, nil, nil, "Failed to detect repo. Provide full reference (owner/repo#N): " .. stderr)
        return
      end
      local ok, data = pcall(vim.json.decode, stdout)
      if not ok or not data then
        callback(nil, nil, nil, "Failed to parse repo info: " .. stdout)
        return
      end
      local owner = data.owner
      if type(owner) == "table" then
        owner = owner.login or owner.name or ""
      end
      callback(owner, data.name, tonumber(num), nil)
    end)
    return
  end

  callback(nil, nil, nil, "Invalid PR reference: " .. pr_ref .. ". Expected #123, owner/repo#123, or a GitHub URL.")
end

---Fetch PR metadata.
---@param owner string
---@param repo string
---@param number number
---@param callback fun(info: docent.PRInfo|nil, err: string|nil)
function M.fetch_pr_info(owner, repo, number, callback)
  local gh = config.get().gh_cmd
  local pr_ref = string.format("%s/%s", owner, repo)
  local cmd = {
    gh, "pr", "view", tostring(number),
    "--repo", pr_ref,
    "--json", "title,author,baseRefName,headRefName,url,state,additions,deletions,changedFiles",
  }

  run_gh(cmd, function(stdout, stderr, code)
    if code ~= 0 then
      callback(nil, "gh error: " .. (stderr ~= "" and stderr or "exit code " .. code))
      return
    end
    if stdout == "" then
      callback(nil, "gh returned empty output for PR info")
      return
    end
    local ok, parsed = pcall(vim.json.decode, stdout)
    if not ok then
      callback(nil, "Failed to parse PR info: " .. stdout)
      return
    end
    ---@type docent.PRInfo
    local info = {
      owner = owner,
      repo = repo,
      number = number,
      title = parsed.title or "",
      author = parsed.author and parsed.author.login or "",
      base = parsed.baseRefName or "",
      head = parsed.headRefName or "",
      url = parsed.url or "",
      state = parsed.state or "",
      additions = parsed.additions or 0,
      deletions = parsed.deletions or 0,
      changed_files = parsed.changedFiles or 0,
    }
    callback(info, nil)
  end)
end

---Fetch the PR diff.
---@param owner string
---@param repo string
---@param number number
---@param callback fun(diff: string|nil, err: string|nil)
function M.fetch_diff(owner, repo, number, callback)
  local gh = config.get().gh_cmd
  local pr_ref = string.format("%s/%s", owner, repo)
  local cmd = { gh, "pr", "diff", tostring(number), "--repo", pr_ref }

  run_gh(cmd, function(stdout, stderr, code)
    if code ~= 0 then
      callback(nil, "gh error: " .. (stderr ~= "" and stderr or "exit code " .. code))
      return
    end
    if stdout == "" then
      callback(nil, "gh returned empty diff")
      return
    end
    callback(stdout, nil)
  end)
end

---Post a review comment on a specific file and line.
---Uses `gh pr comment` with file/line reference in the body.
---@param owner string
---@param repo string
---@param number number
---@param file string File path
---@param line number Line number
---@param body string Comment text
---@param callback fun(err: string|nil)
function M.post_comment(owner, repo, number, file, line, body, callback)
  local gh = config.get().gh_cmd
  local pr_ref = string.format("%s/%s", owner, repo)
  local comment = string.format("**%s:%d**\n\n%s", file, line, body)

  local cmd = {
    gh, "pr", "comment", tostring(number),
    "--repo", pr_ref,
    "--body", comment,
  }

  run_gh(cmd, function(_, stderr, code)
    if code == 0 then
      callback(nil)
    else
      callback("Failed to post comment: " .. stderr)
    end
  end)
end

---Submit a PR review (approve or request changes).
---@param owner string
---@param repo string
---@param number number
---@param action "approve"|"request-changes"|"comment"
---@param body? string Optional review message
---@param callback fun(err: string|nil)
function M.submit_review(owner, repo, number, action, body, callback)
  local gh = config.get().gh_cmd
  local pr_ref = string.format("%s/%s", owner, repo)

  local cmd = {
    gh, "pr", "review", tostring(number),
    "--repo", pr_ref,
    "--" .. action,
  }
  if body and body ~= "" then
    table.insert(cmd, "--body")
    table.insert(cmd, body)
  end

  run_gh(cmd, function(_, stderr, code)
    if code == 0 then
      callback(nil)
    else
      callback(string.format("Failed to %s PR: %s", action, stderr))
    end
  end)
end

return M
