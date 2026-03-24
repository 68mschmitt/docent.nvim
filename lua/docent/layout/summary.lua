--- Summary view.
--- Shows PR overview: what changed, AI assessment, finding counts by category.
local helpers = require("docent.ui.helpers")
local session = require("docent.core.session")
local findings_mod = require("docent.core.findings")

local M = {}

---@type number|nil
M.buf = nil

---@type number|nil
M.win = nil

---Open the summary view as a floating window.
function M.open()
  local s = session.get()
  if not s.active then
    vim.notify("[docent] No active review", vim.log.levels.WARN)
    return
  end

  -- Calculate dimensions
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.min(80, ui.width - 4)
  local height = math.min(30, ui.height - 4)

  -- Create buffer
  M.buf = helpers.create_buf("summary")

  -- Build content
  local lines = {}
  local highlights = {} ---@type {line: number, group: string, col_start: number, col_end: number}[]

  -- Title
  local pr = s.pr_info
  local title = pr and string.format("PR Review: %s/%s#%d", pr.owner, pr.repo, pr.number) or "PR Review"
  table.insert(lines, helpers.header(title, width))
  table.insert(highlights, { line = 0, group = "DocentHeader", col_start = 0, col_end = -1 })
  table.insert(lines, "")

  -- PR details
  if pr then
    table.insert(lines, "  " .. pr.title)
    table.insert(highlights, { line = #lines - 1, group = "DocentHeaderAccent", col_start = 0, col_end = -1 })
    table.insert(lines, string.format("  Author: %s  |  %s -> %s", pr.author, pr.base, pr.head))
    table.insert(lines, string.format("  +%d -%d across %d files", pr.additions, pr.deletions, pr.changed_files))
    table.insert(lines, "")
  end

  -- Summary
  table.insert(lines, "  SUMMARY")
  table.insert(highlights, { line = #lines - 1, group = "DocentNoteSection", col_start = 0, col_end = -1 })
  for _, wrapped in ipairs(helpers.wrap_text(s.summary, width - 4)) do
    table.insert(lines, "  " .. wrapped)
  end
  table.insert(lines, "")

  -- Assessment
  table.insert(lines, "  ASSESSMENT")
  table.insert(highlights, { line = #lines - 1, group = "DocentNoteSection", col_start = 0, col_end = -1 })
  for _, wrapped in ipairs(helpers.wrap_text(s.assessment, width - 4)) do
    table.insert(lines, "  " .. wrapped)
  end
  table.insert(lines, "")

  -- Findings breakdown
  local stats = session.stats()
  table.insert(lines, "  FINDINGS (" .. stats.total .. " total)")
  table.insert(highlights, { line = #lines - 1, group = "DocentNoteSection", col_start = 0, col_end = -1 })

  local cat_order = { "bug", "warning", "style", "question", "positive", "info" }
  for _, cat_name in ipairs(cat_order) do
    local count = stats.by_category[cat_name] or 0
    if count > 0 then
      local cat = findings_mod.categories[cat_name]
      local entry = string.format("  %s  %s: %d", cat.marker, cat.label, count)
      table.insert(lines, entry)
      table.insert(highlights, { line = #lines - 1, group = cat.hl, col_start = 0, col_end = -1 })
    end
  end
  table.insert(lines, "")

  -- Status breakdown
  local ack = stats.by_status["acknowledged"] or 0
  local dis = stats.by_status["dismissed"] or 0
  local pen = stats.by_status["pending"] or 0
  table.insert(lines, string.format("  Progress: %d acknowledged, %d dismissed, %d pending", ack, dis, pen))
  table.insert(lines, "")

  -- Footer
  table.insert(lines, "  Press q or <Esc> to close this summary")
  table.insert(highlights, { line = #lines - 1, group = "DocentKeyHint", col_start = 0, col_end = -1 })

  -- Write content
  helpers.set_lines(M.buf, lines)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, M.buf, -1, hl.group, hl.line, hl.col_start, hl.col_end)
  end

  -- Open floating window
  M.win = vim.api.nvim_open_win(M.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((ui.height - height) / 2),
    col = math.floor((ui.width - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Summary ",
    title_pos = "center",
  })

  -- Keymaps to close
  vim.keymap.set("n", "q", M.close, { buffer = M.buf, nowait = true })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = M.buf, nowait = true })
end

---Close the summary view.
function M.close()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
  end
  M.win = nil
  M.buf = nil
end

return M
