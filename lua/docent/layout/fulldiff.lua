--- Full diff view with gutter signs at finding locations.
--- Shows the entire PR diff in a single buffer with sign markers
--- where findings are located.
local helpers = require("docent.ui.helpers")
local session = require("docent.core.session")
local ui_highlights = require("docent.ui.highlights")

local M = {}

---@type number|nil
M.buf = nil

---@type number|nil
M.win = nil

---@type number Namespace for signs/extmarks
local ns = vim.api.nvim_create_namespace("docent_fulldiff")

---Open the full diff view as a floating window.
function M.open()
  local s = session.get()
  if not s.active or not s.diff_text then
    vim.notify("[docent] No active review or diff", vim.log.levels.WARN)
    return
  end

  local ui = vim.api.nvim_list_uis()[1]
  local width = math.min(120, ui.width - 4)
  local height = math.min(40, ui.height - 4)

  M.buf = helpers.create_buf("fulldiff")

  -- Build diff content with line numbers
  local lines = {}
  local highlights = {} ---@type {line: number, group: string, col_start: number, col_end: number}[]
  local finding_lines = {} ---@type {buf_line: number, finding: docent.Finding}[]

  -- Map finding file:line to quickly look them up
  local finding_map = {} ---@type table<string, docent.Finding[]>
  for _, f in ipairs(s.findings) do
    local key = f.file
    if not finding_map[key] then finding_map[key] = {} end
    table.insert(finding_map[key], f)
  end

  local current_file = nil
  local new_line_counter = 0
  local in_hunk = false

  for raw_line in s.diff_text:gmatch("[^\n]+") do
    -- Skip "\ No newline at end of file" markers
    if raw_line:match("^\\") then
      goto continue
    end

    -- File header
    if raw_line:match("^diff %-%-git") then
      current_file = raw_line:match("b/(.+)$") or ""
      in_hunk = false
      table.insert(lines, "")
      table.insert(lines, raw_line)
      table.insert(highlights, { line = #lines - 1, group = "DocentDiffFile", col_start = 0, col_end = -1 })
      goto continue
    end

    -- Metadata lines
    if raw_line:match("^%-%-%- ") or raw_line:match("^%+%+%+ ") or raw_line:match("^index ") then
      table.insert(lines, raw_line)
      table.insert(highlights, { line = #lines - 1, group = "DocentDiffFile", col_start = 0, col_end = -1 })
      goto continue
    end

    -- Hunk header: capture new_start (second capture group)
    local _, new_s = raw_line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@")
    if new_s then
      in_hunk = true
      new_line_counter = tonumber(new_s) - 1
      table.insert(lines, raw_line)
      table.insert(highlights, { line = #lines - 1, group = "DocentDiffHunk", col_start = 0, col_end = -1 })
      goto continue
    end

    if in_hunk then
      local prefix = raw_line:sub(1, 1)
      if prefix == "+" then
        new_line_counter = new_line_counter + 1
        table.insert(lines, string.format("%4d│%s", new_line_counter, raw_line))
        table.insert(highlights, { line = #lines - 1, group = "DocentDiffAdd", col_start = 0, col_end = -1 })
      elseif prefix == "-" then
        table.insert(lines, "    │" .. raw_line)
        table.insert(highlights, { line = #lines - 1, group = "DocentDiffDel", col_start = 0, col_end = -1 })
      else
        new_line_counter = new_line_counter + 1
        table.insert(lines, string.format("%4d│%s", new_line_counter, raw_line:sub(2)))
      end

      -- Check if any finding points to this line
      if current_file and prefix ~= "-" then
        local file_findings = finding_map[current_file]
        if file_findings then
          for _, f in ipairs(file_findings) do
            if f.line == new_line_counter then
              table.insert(finding_lines, { buf_line = #lines - 1, finding = f })
            end
          end
        end
      end
    else
      table.insert(lines, raw_line)
    end

    ::continue::
  end

  -- Write content
  helpers.set_lines(M.buf, lines)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, M.buf, -1, hl.group, hl.line, hl.col_start, hl.col_end)
  end

  -- Place signs at finding locations
  for _, fl in ipairs(finding_lines) do
    local sign_name = ui_highlights.sign_for_category(fl.finding.category)
    pcall(vim.fn.sign_place, 0, "docent_fulldiff", sign_name, M.buf, { lnum = fl.buf_line + 1 })
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
    title = " Full Diff ",
    title_pos = "center",
  })

  vim.wo[M.win].signcolumn = "yes"

  -- Keymaps
  vim.keymap.set("n", "q", M.close, { buffer = M.buf, nowait = true })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = M.buf, nowait = true })

  -- Jump to next/prev finding sign
  vim.keymap.set("n", "]c", function()
    local cursor = vim.api.nvim_win_get_cursor(M.win)
    local current_line = cursor[1]
    for _, fl in ipairs(finding_lines) do
      if fl.buf_line + 1 > current_line then
        vim.api.nvim_win_set_cursor(M.win, { fl.buf_line + 1, 0 })
        vim.cmd("normal! zz")
        return
      end
    end
    -- Wrap to first
    if #finding_lines > 0 then
      vim.api.nvim_win_set_cursor(M.win, { finding_lines[1].buf_line + 1, 0 })
      vim.cmd("normal! zz")
    end
  end, { buffer = M.buf, nowait = true, desc = "Docent: Next finding" })

  vim.keymap.set("n", "[c", function()
    local cursor = vim.api.nvim_win_get_cursor(M.win)
    local current_line = cursor[1]
    for i = #finding_lines, 1, -1 do
      if finding_lines[i].buf_line + 1 < current_line then
        vim.api.nvim_win_set_cursor(M.win, { finding_lines[i].buf_line + 1, 0 })
        vim.cmd("normal! zz")
        return
      end
    end
    -- Wrap to last
    if #finding_lines > 0 then
      vim.api.nvim_win_set_cursor(M.win, { finding_lines[#finding_lines].buf_line + 1, 0 })
      vim.cmd("normal! zz")
    end
  end, { buffer = M.buf, nowait = true, desc = "Docent: Prev finding" })
end

---Close the full diff view.
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
