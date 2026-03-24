--- Session state management.
--- Holds all state for the current review session.
local findings_mod = require("docent.core.findings")

local M = {}

---@class docent.ReviewResult
---@field summary string
---@field assessment string
---@field findings table[] Raw findings from AI

---@alias docent.StageStatus "pending"|"active"|"done"|"error"

---@class docent.Stage
---@field id string Unique stage identifier
---@field label string Display label
---@field status docent.StageStatus
---@field detail? string Optional detail text (e.g., error message or PR title)

---@class docent.Session
---@field active boolean Whether a review session is active
---@field loading boolean Whether the review is still being generated
---@field stages docent.Stage[] Pipeline stages shown during loading
---@field pr_info docent.PRInfo|nil PR metadata
---@field diff_text string|nil Raw unified diff text
---@field diff_files docent.DiffFile[] Parsed diff files
---@field review docent.ReviewResult|nil Raw AI review response
---@field findings docent.Finding[] Processed findings list
---@field current_index number Currently focused finding (1-indexed)
---@field summary string PR summary from AI
---@field assessment string Overall assessment from AI

---@class docent.DiffFile
---@field path string File path
---@field hunks docent.DiffHunk[] Diff hunks
---@field header string The diff header line (--- a/... +++ b/...)
---@field lines string[] All diff lines for this file

---@class docent.DiffHunk
---@field old_start number
---@field old_count number
---@field new_start number
---@field new_count number
---@field header string The @@ line
---@field lines string[] Lines in this hunk

---The default pipeline stages shown during review generation.
---@return docent.Stage[]
local function default_stages()
  return {
    { id = "resolve",   label = "Resolving PR",              status = "pending" },
    { id = "checkout",  label = "Checking out PR branch",    status = "pending" },
    { id = "server",    label = "Connecting to OpenCode",     status = "pending" },
    { id = "fetch",     label = "Fetching PR data",           status = "pending" },
    { id = "session",   label = "Creating review session",    status = "pending" },
    { id = "review",    label = "AI is reviewing the PR",     status = "pending" },
  }
end

---@type docent.Session
local session = {
  active = false,
  loading = false,
  stages = {},
  pr_info = nil,
  diff_text = nil,
  diff_files = {},
  review = nil,
  findings = {},
  current_index = 1,
  summary = "",
  assessment = "",
}

---Reset the session to initial state.
function M.reset()
  session = {
    active = false,
    loading = false,
    stages = {},
    pr_info = nil,
    diff_text = nil,
    diff_files = {},
    review = nil,
    findings = {},
    current_index = 1,
    summary = "",
    assessment = "",
  }
end

---Get the current session.
---@return docent.Session
function M.get()
  return session
end

---Check if a session is active (review complete, walkthrough mode).
---@return boolean
function M.is_active()
  return session.active
end

---Check if a review is being generated (loading mode).
---@return boolean
function M.is_loading()
  return session.loading
end

---Start the loading pipeline: initialize stages and set loading mode.
function M.start_loading()
  session.loading = true
  session.active = false
  session.stages = default_stages()
end

---Update a stage's status and optional detail text.
---@param stage_id string
---@param status docent.StageStatus
---@param detail? string
function M.update_stage(stage_id, status, detail)
  for _, stage in ipairs(session.stages) do
    if stage.id == stage_id then
      stage.status = status
      if detail then
        stage.detail = detail
      end
      break
    end
  end
end

---Set PR info.
---@param info docent.PRInfo
function M.set_pr_info(info)
  session.pr_info = info
end

---Set the raw diff text and parse it into files.
---@param diff string
function M.set_diff(diff)
  session.diff_text = diff
  session.diff_files = M.parse_diff(diff)
end

---Set the AI review result and build the findings list.
---Transitions from loading to active mode.
---@param review docent.ReviewResult
function M.set_review(review)
  session.review = review
  session.summary = review.summary or ""
  session.assessment = review.assessment or ""
  session.findings = {}
  for i, raw in ipairs(review.findings or {}) do
    table.insert(session.findings, findings_mod.from_raw(raw, i))
  end
  session.findings = findings_mod.sort(session.findings)
  session.current_index = #session.findings > 0 and 1 or 0
  session.loading = false
  session.active = true
end

---Get the currently focused finding.
---@return docent.Finding|nil
function M.current_finding()
  if session.current_index > 0 and session.current_index <= #session.findings then
    return session.findings[session.current_index]
  end
  return nil
end

---Move to the next finding. Wraps around.
---@return docent.Finding|nil
function M.next_finding()
  if #session.findings == 0 then return nil end
  session.current_index = session.current_index % #session.findings + 1
  return M.current_finding()
end

---Move to the previous finding. Wraps around.
---@return docent.Finding|nil
function M.prev_finding()
  if #session.findings == 0 then return nil end
  session.current_index = (session.current_index - 2) % #session.findings + 1
  return M.current_finding()
end

---Go to a specific finding by index.
---@param index number
---@return docent.Finding|nil
function M.goto_finding(index)
  if index >= 1 and index <= #session.findings then
    session.current_index = index
    return M.current_finding()
  end
  return nil
end

---Acknowledge the current finding.
function M.acknowledge_current()
  local f = M.current_finding()
  if f then f.status = "acknowledged" end
end

---Dismiss the current finding.
function M.dismiss_current()
  local f = M.current_finding()
  if f then f.status = "dismissed" end
end

---Add a chat message to the current finding.
---@param role "user"|"ai"
---@param text string
function M.add_chat_message(role, text)
  local f = M.current_finding()
  if f then
    table.insert(f.chat, { role = role, text = text })
  end
end

---Get the diff file that matches a file path.
---@param path string
---@return docent.DiffFile|nil
function M.get_diff_file(path)
  for _, df in ipairs(session.diff_files) do
    if df.path == path then
      return df
    end
  end
  return nil
end

---Get the next file that has findings (relative to current finding).
---@param direction number 1 for next, -1 for previous
---@return docent.Finding|nil
function M.next_finding_file(direction)
  local current = M.current_finding()
  if not current then return nil end
  local current_file = current.file
  local idx = session.current_index
  while true do
    idx = idx + direction
    if idx < 1 then idx = #session.findings end
    if idx > #session.findings then idx = 1 end
    if idx == session.current_index then return nil end -- wrapped all the way around
    if session.findings[idx].file ~= current_file then
      session.current_index = idx
      return M.current_finding()
    end
  end
end

---Parse a unified diff into structured DiffFile objects.
---@param diff string
---@return docent.DiffFile[]
function M.parse_diff(diff)
  local files = {}
  local current_file = nil
  local current_hunk = nil

  for line in diff:gmatch("[^\n]+") do
    -- Skip "\ No newline at end of file" markers
    if line:match("^\\") then
      if current_file then
        table.insert(current_file.lines, line)
      end
      goto continue
    end

    -- New file header: diff --git a/path b/path
    if line:match("^diff %-%-git") then
      if current_hunk and current_file then
        table.insert(current_file.hunks, current_hunk)
      end
      if current_file then
        table.insert(files, current_file)
      end
      local path = line:match("b/(.+)$") or ""
      current_file = {
        path = path,
        hunks = {},
        header = line,
        lines = { line },
      }
      current_hunk = nil

    elseif current_file then
      table.insert(current_file.lines, line)

      -- Hunk header: @@ -old_start,old_count +new_start,new_count @@
      local old_s, old_c, new_s, new_c = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
      if old_s then
        if current_hunk then
          table.insert(current_file.hunks, current_hunk)
        end
        current_hunk = {
          old_start = tonumber(old_s),
          old_count = tonumber(old_c) or 1,
          new_start = tonumber(new_s),
          new_count = tonumber(new_c) or 1,
          header = line,
          lines = { line },
        }
      elseif current_hunk then
        table.insert(current_hunk.lines, line)
      end
    end

    ::continue::
  end

  -- Flush last hunk and file
  if current_hunk and current_file then
    table.insert(current_file.hunks, current_hunk)
  end
  if current_file then
    table.insert(files, current_file)
  end

  return files
end

---Get summary stats for the review.
---@return {total: number, by_category: table<string, number>, by_status: table<string, number>}
function M.stats()
  local by_cat = {}
  local by_status = {}
  for _, f in ipairs(session.findings) do
    by_cat[f.category] = (by_cat[f.category] or 0) + 1
    by_status[f.status] = (by_status[f.status] or 0) + 1
  end
  return {
    total = #session.findings,
    by_category = by_cat,
    by_status = by_status,
  }
end

---Serialize the session to a table that can be JSON-encoded and saved to disk.
---Only includes the data needed to reconstruct the review walkthrough.
---@return table|nil serialized Returns nil if no active session
function M.serialize()
  if not session.active then return nil end

  -- Serialize findings (strip functions, keep data)
  local findings_data = {}
  for _, f in ipairs(session.findings) do
    table.insert(findings_data, {
      index = f.index,
      category = f.category,
      title = f.title,
      file = f.file,
      line = f.line,
      end_line = f.end_line,
      explanation = f.explanation,
      learning = f.learning,
      suggestion = f.suggestion,
      status = f.status,
      chat = f.chat,
    })
  end

  return {
    version = 1,
    pr_info = session.pr_info,
    diff_text = session.diff_text,
    summary = session.summary,
    assessment = session.assessment,
    findings = findings_data,
    current_index = session.current_index,
  }
end

---Restore a session from a serialized table (from disk or from a previous hide).
---@param data table The serialized session data
---@return boolean success
function M.deserialize(data)
  if not data or data.version ~= 1 then
    return false
  end

  session.pr_info = data.pr_info
  session.diff_text = data.diff_text
  if data.diff_text then
    session.diff_files = M.parse_diff(data.diff_text)
  end
  session.summary = data.summary or ""
  session.assessment = data.assessment or ""
  session.current_index = data.current_index or 1
  session.findings = {}
  for _, fd in ipairs(data.findings or {}) do
    table.insert(session.findings, {
      index = fd.index,
      category = fd.category,
      title = fd.title,
      file = fd.file,
      line = fd.line,
      end_line = fd.end_line,
      explanation = fd.explanation,
      learning = fd.learning,
      suggestion = fd.suggestion,
      status = fd.status or "pending",
      chat = fd.chat or {},
    })
  end
  session.loading = false
  session.active = true
  session.stages = {}
  return true
end

return M
