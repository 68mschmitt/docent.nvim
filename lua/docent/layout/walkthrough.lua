--- Walkthrough view.
--- Orchestrates the three-panel layout, synced navigation between panels,
--- and all keybindings within the walkthrough.
local layout = require("docent.layout.manager")
local session = require("docent.core.session")
local findings_list = require("docent.ui.findings_list")
local diff_view = require("docent.ui.diff_view")
local note_panel = require("docent.ui.note_panel")
local ai_client = require("docent.ai.client")
local github = require("docent.github")
local helpers = require("docent.ui.helpers")

local M = {}

---Render all three panels to reflect current session state.
function M.render_all()
  findings_list.render()
  diff_view.render()
  note_panel.render()
end

---Navigate to the next finding and re-render.
function M.next_finding()
  session.next_finding()
  M.render_all()
end

---Navigate to the previous finding and re-render.
function M.prev_finding()
  session.prev_finding()
  M.render_all()
end

---Jump to a finding by index.
---@param index number
function M.goto_finding(index)
  session.goto_finding(index)
  M.render_all()
end

---Jump to the next file that has findings.
function M.next_file()
  session.next_finding_file(1)
  M.render_all()
end

---Jump to the previous file that has findings.
function M.prev_file()
  session.next_finding_file(-1)
  M.render_all()
end

---Acknowledge the current finding and move to next.
function M.acknowledge()
  session.acknowledge_current()
  M.render_all()
end

---Dismiss the current finding and move to next.
function M.dismiss()
  session.dismiss_current()
  M.render_all()
end

---Post a comment on the current finding's location to the PR.
function M.comment()
  local finding = session.current_finding()
  local pr = session.get().pr_info
  if not finding or not pr then
    vim.notify("[docent] No finding or PR info available", vim.log.levels.WARN)
    return
  end

  helpers.input("Comment on " .. finding.file .. ":" .. finding.line, function(text)
    if not text then return end
    github.post_comment(pr.owner, pr.repo, pr.number, finding.file, finding.line, text, function(err)
      if err then
        vim.notify("[docent] " .. err, vim.log.levels.ERROR)
      else
        vim.notify("[docent] Comment posted", vim.log.levels.INFO)
      end
    end)
  end)
end

---Ask a follow-up question about the current finding.
function M.followup()
  local finding = session.current_finding()
  if not finding then
    vim.notify("[docent] No finding selected", vim.log.levels.WARN)
    return
  end

  -- Open chat panel if not already open
  if not note_panel.chat_open then
    note_panel.open_chat()
  end

  helpers.input("Ask about: " .. finding.title, function(question)
    if not question then return end

    -- Add user message to chat
    session.add_chat_message("user", question)
    note_panel.render_chat()

    -- Build context for the AI
    local context = string.format(
      "%s\nFile: %s, Line: %d\nExplanation: %s\nLearning: %s",
      finding.title,
      finding.file,
      finding.line,
      finding.explanation,
      finding.learning
    )

    -- Show loading state
    session.add_chat_message("ai", "Thinking...")
    note_panel.render_chat()

    ai_client.ask_followup(context, question, function(answer, err)
      -- Remove the "Thinking..." message
      local chat = finding.chat
      if #chat > 0 and chat[#chat].text == "Thinking..." then
        table.remove(chat)
      end

      if err then
        session.add_chat_message("ai", "Error: " .. err)
      else
        session.add_chat_message("ai", answer or "No response")
      end
      note_panel.render_chat()
    end)
  end)
end

---Approve the PR.
function M.approve()
  local pr = session.get().pr_info
  if not pr then
    vim.notify("[docent] No PR info available", vim.log.levels.WARN)
    return
  end

  helpers.input("Approve message (optional, press Enter to skip)", function(msg)
    github.submit_review(pr.owner, pr.repo, pr.number, "approve", msg, function(err)
      if err then
        vim.notify("[docent] " .. err, vim.log.levels.ERROR)
      else
        vim.notify("[docent] PR approved", vim.log.levels.INFO)
      end
    end)
  end)
end

---Request changes on the PR.
function M.request_changes()
  local pr = session.get().pr_info
  if not pr then
    vim.notify("[docent] No PR info available", vim.log.levels.WARN)
    return
  end

  helpers.input("Request changes message", function(msg)
    if not msg then
      vim.notify("[docent] Message required for requesting changes", vim.log.levels.WARN)
      return
    end
    github.submit_review(pr.owner, pr.repo, pr.number, "request-changes", msg, function(err)
      if err then
        vim.notify("[docent] " .. err, vim.log.levels.ERROR)
      else
        vim.notify("[docent] Changes requested", vim.log.levels.INFO)
      end
    end)
  end)
end

---Close the walkthrough and clean up.
---Restores the original git branch and pops the stash if one was created.
function M.close()
  note_panel.close_chat()
  diff_view.close_terminal()
  layout.close()
  session.reset()
  ai_client.shutdown()

  -- Restore original branch and pop stash
  local git = require("docent.core.git")
  git.restore(function(err)
    if err then
      vim.notify("[docent] " .. err, vim.log.levels.WARN)
    end
  end)
end

---Set up keymaps for all walkthrough buffers.
function M.setup_keymaps()
  local bufs = {
    findings_list.buf,
    diff_view.buf,
    note_panel.buf,
  }

  local shared_maps = {
    { "q", M.close,           "Close review" },
    { "c", M.comment,         "Comment on PR" },
    { "?", M.followup,        "Ask follow-up" },
  }

  for _, buf in ipairs(bufs) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      -- Shared keymaps on all panels
      for _, map in ipairs(shared_maps) do
        vim.keymap.set("n", map[1], map[2], { buffer = buf, desc = "Docent: " .. map[3], nowait = true })
      end
    end
  end

  -- Findings list specific keymaps
  if findings_list.buf and vim.api.nvim_buf_is_valid(findings_list.buf) then
    local buf = findings_list.buf
    vim.keymap.set("n", "j", M.next_finding, { buffer = buf, desc = "Docent: Next finding", nowait = true })
    vim.keymap.set("n", "k", M.prev_finding, { buffer = buf, desc = "Docent: Prev finding", nowait = true })
    vim.keymap.set("n", "<CR>", function() layout.focus("diff") end, { buffer = buf, desc = "Docent: Focus diff", nowait = true })
    vim.keymap.set("n", "a", M.acknowledge, { buffer = buf, desc = "Docent: Acknowledge", nowait = true })
    vim.keymap.set("n", "d", M.dismiss, { buffer = buf, desc = "Docent: Dismiss", nowait = true })
    vim.keymap.set("n", "S", function() require("docent.layout.summary").open() end, { buffer = buf, desc = "Docent: Summary", nowait = true })
    vim.keymap.set("n", "D", function() require("docent.layout.fulldiff").open() end, { buffer = buf, desc = "Docent: Full diff", nowait = true })
    -- Number keys to jump to finding
    for i = 1, 9 do
      vim.keymap.set("n", tostring(i), function() M.goto_finding(i) end, { buffer = buf, desc = "Docent: Go to finding " .. i, nowait = true })
    end
  end

  -- Diff view specific keymaps
  if diff_view.buf and vim.api.nvim_buf_is_valid(diff_view.buf) then
    local buf = diff_view.buf
    vim.keymap.set("n", "]c", M.next_finding, { buffer = buf, desc = "Docent: Next finding", nowait = true })
    vim.keymap.set("n", "[c", M.prev_finding, { buffer = buf, desc = "Docent: Prev finding", nowait = true })
    vim.keymap.set("n", "]f", M.next_file, { buffer = buf, desc = "Docent: Next file", nowait = true })
    vim.keymap.set("n", "[f", M.prev_file, { buffer = buf, desc = "Docent: Prev file", nowait = true })
    vim.keymap.set("n", "<Tab>", function() layout.focus("findings") end, { buffer = buf, desc = "Docent: Focus findings", nowait = true })
  end

  -- Note panel specific keymaps
  if note_panel.buf and vim.api.nvim_buf_is_valid(note_panel.buf) then
    local buf = note_panel.buf
    vim.keymap.set("n", "a", M.acknowledge, { buffer = buf, desc = "Docent: Acknowledge", nowait = true })
    vim.keymap.set("n", "d", M.dismiss, { buffer = buf, desc = "Docent: Dismiss", nowait = true })
    vim.keymap.set("n", "<Tab>", function() layout.focus("findings") end, { buffer = buf, desc = "Docent: Focus findings", nowait = true })
    vim.keymap.set("n", "<Esc>", function()
      if note_panel.chat_open then
        note_panel.close_chat()
      end
    end, { buffer = buf, desc = "Docent: Close chat", nowait = true })
  end
end

---Open the walkthrough and render all panels.
---Call this after session state has been populated.
function M.open()
  if not layout.open() then
    vim.notify("[docent] Failed to open layout", vim.log.levels.ERROR)
    return
  end
  M.setup_keymaps()
  M.render_all()
end

return M
