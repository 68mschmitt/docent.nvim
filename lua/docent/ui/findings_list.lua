--- Findings list panel (left panel).
--- Has two modes:
---   Loading: shows pipeline stages with progress indicators
---   Active:  shows the list of findings with category markers and status
local helpers = require("docent.ui.helpers")
local session = require("docent.core.session")
local findings_mod = require("docent.core.findings")

local M = {}

---@type number|nil
M.buf = nil

---The keymap hints shown in the footer when in active (review) mode.
local review_hints = {
  { key = "j/k",  desc = "navigate" },
  { key = "⏎",    desc = "focus diff" },
  { key = "a",    desc = "acknowledge" },
  { key = "d",    desc = "dismiss" },
  { key = "c",    desc = "comment" },
  { key = "?",    desc = "follow-up" },
  { key = "q",    desc = "hide" },
  { key = "Q",    desc = "close" },
}

---The keymap hints shown in the footer when in loading mode.
local loading_hints = {
  { key = "q", desc = "cancel" },
}

---Stage status markers.
local stage_markers = {
  pending = "  ·  ",
  active  = "  ◌  ",
  done    = "  ✓  ",
  error   = "  ✗  ",
}

---Stage status highlight groups.
local stage_highlights = {
  pending = "DocentKeyHint",
  active  = "DocentHeaderAccent",
  done    = "DocentPositive",
  error   = "DocentBug",
}

---Create the findings list buffer.
---@return number buf
function M.create()
  M.buf = helpers.create_buf("findings")
  return M.buf
end

---Render the panel. Automatically chooses loading or active mode.
function M.render()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  if session.is_loading() then
    M.render_loading()
  elseif session.is_active() then
    M.render_findings()
  else
    M.render_empty()
  end
end

---Render the loading/stages view.
function M.render_loading()
  local s = session.get()
  local width = 30
  local win = M.get_win()
  if win then
    width = vim.api.nvim_win_get_width(win)
  end

  local lines = {}
  local highlights = {} ---@type {line: number, group: string, col_start: number, col_end: number}[]

  -- Header
  table.insert(lines, helpers.header_left("Review Progress", width))
  table.insert(highlights, { line = 0, group = "DocentHeader", col_start = 0, col_end = -1 })
  table.insert(lines, "")

  -- PR info if available
  if s.pr_info then
    local pr_label = string.format("  #%d %s", s.pr_info.number, s.pr_info.title)
    if vim.api.nvim_strwidth(pr_label) > width then
      pr_label = pr_label:sub(1, width - 2) .. "…"
    end
    table.insert(lines, pr_label)
    table.insert(highlights, { line = #lines - 1, group = "DocentHeaderAccent", col_start = 0, col_end = -1 })
    if s.pr_info.author ~= "" then
      table.insert(lines, "  by " .. s.pr_info.author)
      table.insert(highlights, { line = #lines - 1, group = "DocentKeyHint", col_start = 0, col_end = -1 })
    end
    table.insert(lines, "")
  end

  -- Stage entries
  for _, stage in ipairs(s.stages) do
    local marker = stage_markers[stage.status] or stage_markers.pending
    local entry = marker .. stage.label
    if stage.status == "active" then
      entry = entry .. "..."
    end

    -- Truncate if needed
    if vim.api.nvim_strwidth(entry) > width then
      entry = entry:sub(1, width - 2) .. "…"
    end
    table.insert(lines, entry)

    local line_idx = #lines - 1
    local hl = stage_highlights[stage.status] or stage_highlights.pending
    -- Highlight the marker
    table.insert(highlights, { line = line_idx, group = hl, col_start = 0, col_end = #marker })
    -- Highlight the label dimmer for pending stages
    if stage.status == "pending" then
      table.insert(highlights, { line = line_idx, group = "DocentKeyHint", col_start = #marker, col_end = -1 })
    end

    -- Show detail on next line if present (e.g., error message)
    if stage.detail and stage.detail ~= "" then
      local detail = "     " .. stage.detail
      if vim.api.nvim_strwidth(detail) > width then
        detail = detail:sub(1, width - 2) .. "…"
      end
      table.insert(lines, detail)
      table.insert(highlights, { line = #lines - 1, group = "DocentKeyHint", col_start = 0, col_end = -1 })
    end
  end

  -- Pad
  local min_lines = 12
  while #lines < min_lines do
    table.insert(lines, "")
  end

  -- Footer
  table.insert(lines, "")
  local footer = helpers.footer_hints(loading_hints, width)
  table.insert(lines, footer)

  -- Write
  helpers.set_lines(M.buf, lines)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, M.buf, -1, hl.group, hl.line, hl.col_start, hl.col_end)
  end
  helpers.apply_footer_highlights(M.buf, #lines - 1, loading_hints)
end

---Render the active findings list view.
function M.render_findings()
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
    if vim.api.nvim_strwidth(entry) > width then
      entry = entry:sub(1, width - 1) .. "…"
    end
    table.insert(lines, entry)

    local line_idx = #lines - 1
    local cat = findings_mod.categories[finding.category] or findings_mod.categories.info

    if is_current then
      table.insert(highlights, { line = line_idx, group = "DocentCurrent", col_start = 0, col_end = -1 })
    elseif finding.status == "acknowledged" then
      table.insert(highlights, { line = line_idx, group = "DocentAcknowledged", col_start = 0, col_end = -1 })
    elseif finding.status == "dismissed" then
      table.insert(highlights, { line = line_idx, group = "DocentDismissed", col_start = 0, col_end = -1 })
    else
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
  local footer = helpers.footer_hints(review_hints, width)
  table.insert(lines, footer)

  -- Write to buffer
  helpers.set_lines(M.buf, lines)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, M.buf, -1, hl.group, hl.line, hl.col_start, hl.col_end)
  end

  -- Apply footer highlights
  helpers.apply_footer_highlights(M.buf, #lines - 1, review_hints)

  -- Position cursor on current finding
  -- Lines: [0]=header, [1]=blank, [2..]=findings (0-indexed)
  -- In 1-indexed cursor coords: finding N is at line N+2
  if win and s.current_index > 0 then
    local cursor_line = s.current_index + 2
    local total_lines = vim.api.nvim_buf_line_count(M.buf)
    if cursor_line >= 1 and cursor_line <= total_lines then
      pcall(vim.api.nvim_win_set_cursor, win, { cursor_line, 0 })
    end
  end
end

---Render an empty/idle state.
function M.render_empty()
  local width = 30
  local win = M.get_win()
  if win then
    width = vim.api.nvim_win_get_width(win)
  end

  local lines = {
    helpers.header_left("Docent", width),
    "",
    "  No active review.",
    "",
    "  :DocentReview <pr>",
    "  to start a review.",
  }
  helpers.set_lines(M.buf, lines)
  pcall(vim.api.nvim_buf_add_highlight, M.buf, -1, "DocentHeader", 0, 0, -1)
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
