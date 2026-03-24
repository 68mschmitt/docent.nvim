--- Findings data model.
--- Represents a single review finding and provides helpers for display.
local M = {}

---@alias docent.FindingCategory "bug"|"warning"|"style"|"question"|"positive"|"info"
---@alias docent.FindingStatus "pending"|"acknowledged"|"dismissed"

---@class docent.Finding
---@field index number Position in the findings list (1-indexed)
---@field category docent.FindingCategory
---@field title string
---@field file string
---@field line number
---@field end_line? number
---@field explanation string
---@field learning string
---@field suggestion? string
---@field status docent.FindingStatus
---@field chat docent.ChatMessage[] Per-finding chat history

---@class docent.ChatMessage
---@field role "user"|"ai"
---@field text string

---Category display info: marker, label, sort priority.
---@type table<docent.FindingCategory, {marker: string, label: string, priority: number, hl: string}>
M.categories = {
  bug      = { marker = "!!", label = "Bug",      priority = 1, hl = "DocentBug" },
  warning  = { marker = "! ", label = "Warning",  priority = 2, hl = "DocentWarning" },
  style    = { marker = "~ ", label = "Style",    priority = 3, hl = "DocentStyle" },
  question = { marker = "? ", label = "Question", priority = 4, hl = "DocentQuestion" },
  positive = { marker = "+ ", label = "Positive", priority = 5, hl = "DocentPositive" },
  info     = { marker = "i ", label = "Info",     priority = 6, hl = "DocentInfo" },
}

---Status display info.
---@type table<docent.FindingStatus, {marker: string, hl: string}>
M.statuses = {
  pending      = { marker = " ", hl = "DocentPending" },
  acknowledged = { marker = "✓", hl = "DocentAcknowledged" },
  dismissed    = { marker = "✗", hl = "DocentDismissed" },
}

---Create a Finding from raw AI response data.
---@param raw table Raw finding from AI structured output
---@param index number
---@return docent.Finding
function M.from_raw(raw, index)
  return {
    index = index,
    category = raw.category or "info",
    title = raw.title or "Untitled finding",
    file = raw.file or "",
    line = raw.line or 1,
    end_line = raw.end_line,
    explanation = raw.explanation or "",
    learning = raw.learning or "",
    suggestion = raw.suggestion,
    status = "pending",
    chat = {},
  }
end

---Format a finding for the list panel: "!! 1  Token validation gap"
---@param finding docent.Finding
---@param is_current boolean
---@return string
function M.format_list_entry(finding, is_current)
  local cat = M.categories[finding.category] or M.categories.info
  local stat = M.statuses[finding.status] or M.statuses.pending
  local cursor = is_current and "▸" or " "
  local status_marker = finding.status == "pending" and " " or stat.marker

  return string.format(
    "%s%s%s %d  %s",
    cursor,
    status_marker,
    cat.marker,
    finding.index,
    finding.title
  )
end

---Sort findings by category priority then file order.
---@param findings docent.Finding[]
---@return docent.Finding[]
function M.sort(findings)
  table.sort(findings, function(a, b)
    local pa = (M.categories[a.category] or M.categories.info).priority
    local pb = (M.categories[b.category] or M.categories.info).priority
    if pa ~= pb then return pa < pb end
    if a.file ~= b.file then return a.file < b.file end
    return a.line < b.line
  end)
  -- Re-index after sort
  for i, f in ipairs(findings) do
    f.index = i
  end
  return findings
end

return M
