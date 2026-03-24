--- Note panel (bottom panel).
--- Shows the WHAT / WHY IT MATTERS / LEARNING / SUGGESTION sections for
--- the current finding. Splits vertically to show a per-finding chat
--- when a follow-up is requested.
local helpers = require("docent.ui.helpers")
local session = require("docent.core.session")
local findings_mod = require("docent.core.findings")

local M = {}

---@type number|nil Main note buffer
M.buf = nil

---@type number|nil Chat buffer (right side when split)
M.chat_buf = nil

---@type number|nil Chat window
M.chat_win = nil

---@type boolean Whether the chat split is open
M.chat_open = false

---Keymap hints for the note panel (without chat).
local note_hints = {
  { key = "a", desc = "acknowledge" },
  { key = "d", desc = "dismiss" },
  { key = "c", desc = "comment" },
  { key = "?", desc = "follow-up" },
  { key = "q", desc = "close" },
}

---Keymap hints for the chat panel.
local chat_hints = {
  { key = "?",     desc = "ask another" },
  { key = "<Esc>", desc = "close chat" },
}

---Create the note buffer.
---@return number buf
function M.create()
  M.buf = helpers.create_buf("note")
  return M.buf
end

---Render the note for the current finding.
function M.render()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  local finding = session.current_finding()
  local s = session.get()
  local stats = session.stats()

  local width = 60
  local win = M.get_win()
  if win then
    -- Width reflects actual note panel width (narrower when chat is open)
    width = vim.api.nvim_win_get_width(win)
  end

  if not finding then
    local lines = {
      helpers.header_left("Note", width),
      "",
      "  No finding selected.",
    }
    helpers.set_lines(M.buf, lines)
    vim.api.nvim_buf_add_highlight(M.buf, -1, "DocentHeader", 0, 0, -1)
    return
  end

  local cat = findings_mod.categories[finding.category] or findings_mod.categories.info
  local lines = {}
  local highlights = {} ---@type {line: number, group: string, col_start: number, col_end: number}[]

  -- Header: "─ Note: Race condition risk [!] ─────────"
  local header_text = string.format("Note: %s [%s]", finding.title, cat.label)
  table.insert(lines, helpers.header_left(header_text, width))
  table.insert(highlights, { line = 0, group = "DocentHeader", col_start = 0, col_end = -1 })
  table.insert(lines, "")

  -- Content width for text wrapping (leave 2 char margin each side)
  local content_width = width - 4

  -- WHAT section (explanation)
  table.insert(lines, "  WHAT")
  table.insert(highlights, { line = #lines - 1, group = "DocentNoteSection", col_start = 0, col_end = -1 })
  for _, wrapped in ipairs(helpers.wrap_text(finding.explanation, content_width)) do
    table.insert(lines, "  " .. wrapped)
  end
  table.insert(lines, "")

  -- WHY IT MATTERS (derived from explanation -- the explanation field covers both what and why)
  -- We split this from learning to keep sections distinct
  -- (The AI prompt asks for explanation to cover "what + why it matters")

  -- LEARNING section
  table.insert(lines, "  LEARNING")
  table.insert(highlights, { line = #lines - 1, group = "DocentNoteSection", col_start = 0, col_end = -1 })
  for _, wrapped in ipairs(helpers.wrap_text(finding.learning, content_width)) do
    table.insert(lines, "  " .. wrapped)
  end
  table.insert(lines, "")

  -- SUGGESTION section (only if present)
  if finding.suggestion and finding.suggestion ~= "" then
    table.insert(lines, "  SUGGESTION")
    table.insert(highlights, { line = #lines - 1, group = "DocentNoteSection", col_start = 0, col_end = -1 })
    for _, wrapped in ipairs(helpers.wrap_text(finding.suggestion, content_width)) do
      table.insert(lines, "  " .. wrapped)
    end
    table.insert(lines, "")
  end

  -- Footer with hints and position
  local position_str = string.format("[%d/%d]", finding.index, stats.total)
  local footer = helpers.footer_hints(note_hints, width - #position_str - 2)
  table.insert(lines, footer .. "  " .. position_str)

  -- Write to buffer
  helpers.set_lines(M.buf, lines)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(M.buf, -1, hl.group, hl.line, hl.col_start, hl.col_end)
  end

  -- Apply footer highlights
  helpers.apply_footer_highlights(M.buf, #lines - 1, note_hints)

  -- If chat is open, also render the chat
  if M.chat_open then
    M.render_chat()
  end
end

---Open the chat split to the right of the note panel.
function M.open_chat()
  if M.chat_open then return end

  local note_win = M.get_win()
  if not note_win then return end

  local cfg = require("docent.config").get()

  -- Create chat buffer
  M.chat_buf = helpers.create_buf("chat")

  -- Split the note window vertically (always to the right)
  vim.api.nvim_set_current_win(note_win)
  vim.cmd("rightbelow vsplit")
  M.chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.chat_win, M.chat_buf)

  -- Set chat window width based on config percentage
  local total_width = vim.api.nvim_win_get_width(note_win) + vim.api.nvim_win_get_width(M.chat_win) + 1
  local chat_width = math.floor(total_width * cfg.layout.chat_panel_width / 100)
  vim.api.nvim_win_set_width(M.chat_win, chat_width)

  -- Window options
  vim.wo[M.chat_win].number = false
  vim.wo[M.chat_win].relativenumber = false
  vim.wo[M.chat_win].signcolumn = "no"
  vim.wo[M.chat_win].wrap = true
  vim.wo[M.chat_win].winfixwidth = true

  -- Guard against manual close of chat window: clean up state
  local chat_augroup = vim.api.nvim_create_augroup("DocentChat", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = chat_augroup,
    pattern = tostring(M.chat_win),
    once = true,
    callback = function()
      M.chat_win = nil
      M.chat_open = false
      if M.chat_buf and vim.api.nvim_buf_is_valid(M.chat_buf) then
        vim.api.nvim_buf_delete(M.chat_buf, { force = true })
      end
      M.chat_buf = nil
      pcall(vim.api.nvim_del_augroup_by_id, chat_augroup)
      -- Re-render note at full width
      vim.schedule(function() M.render() end)
    end,
  })

  M.chat_open = true
  M.render_chat()
  M.render() -- Re-render note at new width

  -- Return focus to note
  vim.api.nvim_set_current_win(note_win)
end

---Close the chat split.
function M.close_chat()
  if not M.chat_open then return end

  if M.chat_win and vim.api.nvim_win_is_valid(M.chat_win) then
    vim.api.nvim_win_close(M.chat_win, true)
  end
  if M.chat_buf and vim.api.nvim_buf_is_valid(M.chat_buf) then
    vim.api.nvim_buf_delete(M.chat_buf, { force = true })
  end

  M.chat_win = nil
  M.chat_buf = nil
  M.chat_open = false
  M.render() -- Re-render note at full width
end

---Toggle the chat split.
function M.toggle_chat()
  if M.chat_open then
    M.close_chat()
  else
    M.open_chat()
  end
end

---Render the chat panel for the current finding.
function M.render_chat()
  if not M.chat_buf or not vim.api.nvim_buf_is_valid(M.chat_buf) then return end

  local finding = session.current_finding()
  if not finding then return end

  local width = 40
  if M.chat_win and vim.api.nvim_win_is_valid(M.chat_win) then
    width = vim.api.nvim_win_get_width(M.chat_win)
  end

  local lines = {}
  local highlights = {} ---@type {line: number, group: string, col_start: number, col_end: number}[]

  -- Header
  local header_text = string.format("Chat: %s", finding.title)
  if #header_text > width - 4 then
    header_text = header_text:sub(1, width - 7) .. "..."
  end
  table.insert(lines, helpers.header_left(header_text, width))
  table.insert(highlights, { line = 0, group = "DocentHeader", col_start = 0, col_end = -1 })
  table.insert(lines, "")

  local content_width = width - 4

  if #finding.chat == 0 then
    table.insert(lines, "  No messages yet.")
    table.insert(lines, "  Press ? to ask a question.")
    table.insert(highlights, { line = #lines - 1, group = "DocentKeyHint", col_start = 0, col_end = -1 })
  else
    for _, msg in ipairs(finding.chat) do
      local prefix = msg.role == "user" and "You" or "AI"
      local hl_group = msg.role == "user" and "DocentChatUser" or "DocentChatAI"

      table.insert(lines, "  " .. prefix .. ":")
      table.insert(highlights, { line = #lines - 1, group = hl_group, col_start = 0, col_end = -1 })

      for _, wrapped in ipairs(helpers.wrap_text(msg.text, content_width)) do
        table.insert(lines, "  " .. wrapped)
      end
      table.insert(lines, "")
    end
  end

  -- Footer
  local footer = helpers.footer_hints(chat_hints, width)
  -- Pad to push footer to bottom
  local min_lines = 6
  while #lines < min_lines do
    table.insert(lines, "")
  end
  table.insert(lines, footer)

  -- Write to buffer
  helpers.set_lines(M.chat_buf, lines)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, M.chat_buf, -1, hl.group, hl.line, hl.col_start, hl.col_end)
  end

  -- Scroll to bottom of chat
  if M.chat_win and vim.api.nvim_win_is_valid(M.chat_win) then
    local line_count = vim.api.nvim_buf_line_count(M.chat_buf)
    pcall(vim.api.nvim_win_set_cursor, M.chat_win, { line_count, 0 })
  end
end

---Get the window displaying the note buffer.
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

---Clean up all note panel resources.
function M.destroy()
  M.close_chat()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
  end
  M.buf = nil
end

return M
