--- Findings list panel (left panel).
--- Renders the list of findings with category markers and status indicators.
local helpers = require("docent.ui.helpers")
local session = require("docent.core.session")
local findings_mod = require("docent.core.findings")

local M = {}

---@type number|nil
M.buf = nil

---The keymap hints shown in the footer of this panel.
local hints = {
  { key = "j/k",  desc = "navigate" },
  { key = "⏎",    desc = "focus diff" },
  { key = "a",    desc = "acknowledge" },
  { key = "d",    desc = "dismiss" },
  { key = "c",    desc = "comment" },
  { key = "?",    desc = "follow-up" },
  { key = "q",    desc = "close" },
}

---Create the findings list buffer.
---@return number buf
function M.create()
  M.buf = helpers.create_buf("findings")
  return M.buf
end

---Render the findings list for the current session state.
function M.render()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  local s = session.get()
  local stats = session.stats()
  local width = 30
  local win = M.get_win()
  if win then
    width = vim.api.nvim_win_get_width(win)
  end

  local lines = {}
  local highlights = {} ---@type {line: number, group: string, col_start: number, col_end: number}[]

  -- Header
  local header_text = string.format("Findings (%d/%d)", s.current_index, stats.total)
  table.insert(lines, helpers.header_left(header_text, width))
  table.insert(highlights, { line = 0, group = "DocentHeader", col_start = 0, col_end = -1 })

  -- Empty line after header
  table.insert(lines, "")

  -- Finding entries
  for _, finding in ipairs(s.findings) do
    local is_current = finding.index == s.current_index
    local entry = findings_mod.format_list_entry(finding, is_current)

    -- Truncate to panel width
    if #entry > width then
      entry = entry:sub(1, width - 1) .. "…"
    end
    table.insert(lines, entry)

    local line_idx = #lines - 1
    local cat = findings_mod.categories[finding.category] or findings_mod.categories.info
    local stat = findings_mod.statuses[finding.status] or findings_mod.statuses.pending

    if is_current then
      table.insert(highlights, { line = line_idx, group = "DocentCurrent", col_start = 0, col_end = -1 })
    elseif finding.status == "acknowledged" then
      table.insert(highlights, { line = line_idx, group = "DocentAcknowledged", col_start = 0, col_end = -1 })
    elseif finding.status == "dismissed" then
      table.insert(highlights, { line = line_idx, group = "DocentDismissed", col_start = 0, col_end = -1 })
    else
      -- Highlight just the category marker
      -- Format: " !! 1  Title" -> marker starts at col 2
      table.insert(highlights, { line = line_idx, group = cat.hl, col_start = 1, col_end = 4 })
    end
  end

  -- Pad to fill panel
  local min_lines = 10
  while #lines < min_lines do
    table.insert(lines, "")
  end

  -- Footer with keymap hints
  table.insert(lines, "")
  local footer = helpers.footer_hints(hints, width)
  table.insert(lines, footer)

  -- Write to buffer
  helpers.set_lines(M.buf, lines)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, M.buf, -1, hl.group, hl.line, hl.col_start, hl.col_end)
  end

  -- Apply footer highlights
  helpers.apply_footer_highlights(M.buf, #lines - 1, hints)

  -- Position cursor on current finding
  -- Lines: [0]=header, [1]=blank, [2..]=findings (0-indexed)
  -- In 1-indexed cursor coords: finding N is at line N+2
  if win and s.current_index > 0 then
    local cursor_line = s.current_index + 2 -- header(1) + blank(1) + index
    local total_lines = vim.api.nvim_buf_line_count(M.buf)
    if cursor_line >= 1 and cursor_line <= total_lines then
      pcall(vim.api.nvim_win_set_cursor, win, { cursor_line, 0 })
    end
  end
end

---Get the window displaying this buffer, if any.
---@return number|nil
function M.get_win()
  if not M.buf then return nil end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == M.buf then
      return win
    end
  end
  return nil
end

---Clean up the buffer.
function M.destroy()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
  end
  M.buf = nil
end

return M
