--- Diff view panel (right panel).
--- Renders the diff for the file referenced by the current finding,
--- scrolled to the relevant line.
local helpers = require("docent.ui.helpers")
local session = require("docent.core.session")

local M = {}

---@type number|nil
M.buf = nil

---@type string|nil Current file being displayed
M.current_file = nil

---Namespace for finding marker extmarks (created once, reused).
local ns = vim.api.nvim_create_namespace("docent_finding_marker")

---The keymap hints for this panel.
local hints = {
  { key = "]c/[c", desc = "next/prev finding" },
  { key = "]f/[f", desc = "next/prev file" },
  { key = "c",     desc = "comment" },
  { key = "<Tab>", desc = "findings list" },
  { key = "q",     desc = "close" },
}

---Create the diff view buffer.
---@return number buf
function M.create()
  M.buf = helpers.create_buf("diff")
  M.current_file = nil
  return M.buf
end

---Render the diff for the current finding's file.
---Scrolls to the relevant line.
function M.render()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  local finding = session.current_finding()
  local s = session.get()

  local width = 60
  local win = M.get_win()
  if win then
    width = vim.api.nvim_win_get_width(win)
  end

  -- Clear previous finding marker extmarks
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)

  if not finding then
    -- No finding selected - show placeholder
    local lines = {
      helpers.header_left("Diff", width),
      "",
      "  No findings to display.",
      "  Run :DocentReview <pr> to start a review.",
    }
    helpers.set_lines(M.buf, lines)
    vim.api.nvim_buf_add_highlight(M.buf, -1, "DocentHeader", 0, 0, -1)
    return
  end

  -- Find the diff file for this finding
  local diff_file = session.get_diff_file(finding.file)

  local lines = {}
  local highlights = {} ---@type {line: number, group: string, col_start: number, col_end: number}[]

  -- Header: shows the file path
  local header_text = string.format("Diff: %s", finding.file)
  table.insert(lines, helpers.header_left(header_text, width))
  table.insert(highlights, { line = 0, group = "DocentHeader", col_start = 0, col_end = -1 })
  table.insert(lines, "")

  if not diff_file then
    table.insert(lines, "  (file not found in diff)")
    helpers.set_lines(M.buf, lines)
    for _, hl in ipairs(highlights) do
      vim.api.nvim_buf_add_highlight(M.buf, -1, hl.group, hl.line, hl.col_start, hl.col_end)
    end
    return
  end

  -- Render diff lines with line numbers
  local target_buf_line = nil -- The buffer line that matches finding.line
  local new_line_counter = 0
  local in_hunk = false

  for _, diff_line in ipairs(diff_file.lines) do
    -- Skip the diff --git header line (already shown in panel header)
    if diff_line:match("^diff %-%-git") then
      goto continue
    end

    -- Skip "\ No newline at end of file" markers
    if diff_line:match("^\\") then
      goto continue
    end

    local line_idx = #lines

    -- File header lines (---, +++, index)
    if diff_line:match("^%-%-%- ") or diff_line:match("^%+%+%+ ") or diff_line:match("^index ") then
      table.insert(lines, diff_line)
      table.insert(highlights, { line = line_idx, group = "DocentDiffFile", col_start = 0, col_end = -1 })
      goto continue
    end

    -- Hunk header: capture new_start (second capture group)
    local _, new_s = diff_line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@")
    if new_s then
      in_hunk = true
      new_line_counter = tonumber(new_s) - 1
      table.insert(lines, diff_line)
      table.insert(highlights, { line = line_idx, group = "DocentDiffHunk", col_start = 0, col_end = -1 })
      goto continue
    end

    if in_hunk then
      local prefix = diff_line:sub(1, 1)

      if prefix == "+" then
        new_line_counter = new_line_counter + 1
        local num_str = string.format("%4d│", new_line_counter)
        local display = num_str .. diff_line
        table.insert(lines, display)
        table.insert(highlights, { line = line_idx, group = "DocentDiffAdd", col_start = 0, col_end = -1 })

        if new_line_counter == finding.line then
          target_buf_line = line_idx
        end

      elseif prefix == "-" then
        local display = "    │" .. diff_line
        table.insert(lines, display)
        table.insert(highlights, { line = line_idx, group = "DocentDiffDel", col_start = 0, col_end = -1 })

      else
        -- Context line
        new_line_counter = new_line_counter + 1
        local num_str = string.format("%4d│", new_line_counter)
        local display = num_str .. diff_line:sub(2) -- Remove the leading space
        table.insert(lines, display)

        if new_line_counter == finding.line then
          target_buf_line = line_idx
        end
      end
    else
      table.insert(lines, diff_line)
    end

    ::continue::
  end

  -- Footer
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

  -- Mark the current finding line with a pointer
  if target_buf_line then
    -- Add a sign or extmark to indicate the finding location
    pcall(vim.api.nvim_buf_set_extmark, M.buf, ns, target_buf_line, 0, {
      sign_text = "▸",
      sign_hl_group = "DocentCurrent",
      priority = 100,
    })
  end

  -- Scroll to the finding line
  if win and target_buf_line then
    -- Center the finding line in the window
    local win_height = vim.api.nvim_win_get_height(win)
    local scroll_line = math.max(1, target_buf_line + 1 - math.floor(win_height / 2))
    pcall(vim.api.nvim_win_set_cursor, win, { target_buf_line + 1, 0 })
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! zz")
    end)
  end

  M.current_file = finding.file
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

---Clean up.
function M.destroy()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
  end
  M.buf = nil
  M.current_file = nil
end

return M
