--- Diff view panel (right panel).
--- During loading: hosts the OpenCode TUI terminal so the user can watch the AI work.
--- During review:  renders the diff for the current finding's file, scrolled to the relevant line.
local helpers = require("docent.ui.helpers")
local session = require("docent.core.session")

local M = {}

---@type number|nil The normal diff buffer
M.buf = nil

---@type number|nil The terminal buffer (when attached to OpenCode session)
M.term_buf = nil

---@type number|nil The terminal job ID
M.term_job = nil

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
  M.term_buf = nil
  M.term_job = nil
  return M.buf
end

---Open a terminal in the diff panel window, replacing the diff buffer.
---Used to show the OpenCode TUI while the AI review is running.
---@param cmd string The shell command to run (e.g., "opencode attach ...")
function M.open_terminal(cmd)
  local win = M.get_win()
  if not win then return end

  -- Create a fresh buffer for the terminal
  M.term_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.term_buf].bufhidden = "hide"

  -- Swap the diff buffer out for the terminal buffer in the same window
  vim.api.nvim_win_set_buf(win, M.term_buf)

  -- Start the terminal process in this buffer
  M.term_job = vim.fn.termopen(cmd, {
    cwd = vim.fn.getcwd(),
    on_exit = function()
      M.term_job = nil
    end,
  })

  -- Terminal mode window options
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  -- Enter terminal mode so the user can see it live
  -- (they can press <C-\><C-n> to get back to normal mode)
  vim.api.nvim_set_current_win(win)
  vim.cmd("startinsert")
end

---Close the terminal and restore the normal diff buffer in the panel.
function M.close_terminal()
  local win = M.get_win_any()
  if not win then return end

  -- Stop the terminal job if still running
  if M.term_job then
    pcall(vim.fn.jobstop, M.term_job)
    M.term_job = nil
  end

  -- Swap back to the diff buffer
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_win_set_buf(win, M.buf)
  end

  -- Clean up the terminal buffer
  if M.term_buf and vim.api.nvim_buf_is_valid(M.term_buf) then
    vim.api.nvim_buf_delete(M.term_buf, { force = true })
  end
  M.term_buf = nil

  -- Restore window options for the diff view
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "yes"
  vim.wo[win].wrap = true
end

---Check if the terminal is currently showing.
---@return boolean
function M.is_terminal_open()
  return M.term_buf ~= nil and vim.api.nvim_buf_is_valid(M.term_buf)
end

---Render the diff for the current finding's file.
---No-op if the terminal is currently showing (don't overwrite it).
function M.render()
  -- If terminal is showing, don't touch the panel
  if M.is_terminal_open() then return end

  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  local finding = session.current_finding()

  local width = 60
  local win = M.get_win()
  if win then
    width = vim.api.nvim_win_get_width(win)
  end

  -- Clear previous finding marker extmarks
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)

  if not finding then
    -- Placeholder: different message for loading vs idle
    local lines = {
      helpers.header_left("Diff", width),
      "",
    }
    if session.is_loading() then
      table.insert(lines, "  Waiting for AI review to complete...")
      table.insert(lines, "")
      table.insert(lines, "  The diff will appear here once")
      table.insert(lines, "  findings are ready.")
    else
      table.insert(lines, "  No findings to display.")
      table.insert(lines, "  Run :DocentReview <pr> to start a review.")
    end
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
    pcall(vim.api.nvim_buf_set_extmark, M.buf, ns, target_buf_line, 0, {
      sign_text = "▸",
      sign_hl_group = "DocentCurrent",
      priority = 100,
    })
  end

  -- Scroll to the finding line
  if win and target_buf_line then
    pcall(vim.api.nvim_win_set_cursor, win, { target_buf_line + 1, 0 })
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! zz")
    end)
  end

  M.current_file = finding.file
end

---Get the window displaying the diff buffer.
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

---Get the window displaying either the diff buffer or the terminal buffer.
---@return number|nil
function M.get_win_any()
  for _, buf in ipairs({ M.buf, M.term_buf }) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
          return win
        end
      end
    end
  end
  return nil
end

---Clean up.
function M.destroy()
  M.close_terminal()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
  end
  M.buf = nil
  M.current_file = nil
end

return M
