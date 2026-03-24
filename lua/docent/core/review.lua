--- Review orchestrator.
--- Coordinates the full review pipeline:
--- open UI -> resolve PR -> connect to OpenCode -> fetch PR data ->
--- create session -> AI review -> transition to walkthrough.
---
--- Opens the three-panel layout immediately and shows stage progress
--- in the findings panel. On completion, transitions to the walkthrough.
local ai_client = require("docent.ai.client")
local github = require("docent.github")
local session = require("docent.core.session")
local layout = require("docent.layout.manager")
local findings_list = require("docent.ui.findings_list")
local diff_view = require("docent.ui.diff_view")
local note_panel = require("docent.ui.note_panel")

local M = {}

---Refresh just the findings panel (used during loading to update stages).
local function refresh_loading()
  findings_list.render()
end

---Refresh all panels with loading-appropriate content.
local function render_loading_state()
  findings_list.render()
  -- Diff and note panels show placeholder during loading
  diff_view.render()
  note_panel.render()
end

---Set a stage to active, update the UI.
---@param stage_id string
---@param detail? string
local function stage_active(stage_id, detail)
  session.update_stage(stage_id, "active", detail)
  refresh_loading()
end

---Set a stage to done, update the UI.
---@param stage_id string
---@param detail? string
local function stage_done(stage_id, detail)
  session.update_stage(stage_id, "done", detail)
  refresh_loading()
end

---Set a stage to error, update the UI.
---@param stage_id string
---@param detail? string
local function stage_error(stage_id, detail)
  session.update_stage(stage_id, "error", detail)
  refresh_loading()
end

---Transition from loading to walkthrough mode.
---Sets up keymaps and renders all panels in active mode.
local function transition_to_walkthrough()
  local walkthrough = require("docent.layout.walkthrough")
  walkthrough.setup_keymaps()
  walkthrough.render_all()
  layout.focus("findings")
end

---Open the layout and show the loading state, then begin the pipeline.
---@param pr_ref string PR reference (#123, owner/repo#123, or URL)
function M.start(pr_ref)
  -- Clean up any existing session
  if session.is_active() or session.is_loading() then
    local walkthrough = require("docent.layout.walkthrough")
    walkthrough.close()
  end
  session.reset()

  -- Initialize loading state
  session.start_loading()

  -- Open the three-panel layout immediately
  if not layout.is_open() then
    if not layout.open() then
      vim.notify("[docent] Failed to open layout", vim.log.levels.ERROR)
      return
    end
  end

  -- Set up a minimal "q to cancel" keymap during loading
  if findings_list.buf and vim.api.nvim_buf_is_valid(findings_list.buf) then
    vim.keymap.set("n", "q", function()
      local walkthrough = require("docent.layout.walkthrough")
      walkthrough.close()
    end, { buffer = findings_list.buf, desc = "Docent: Cancel review", nowait = true })
  end

  -- Show initial loading state
  render_loading_state()

  -- Step 1: Resolve PR reference
  stage_active("resolve")
  github.parse_pr_ref(pr_ref, function(owner, repo, number, parse_err)
    if parse_err then
      stage_error("resolve", parse_err)
      return
    end
    stage_done("resolve", string.format("%s/%s#%d", owner, repo, number))

    -- Step 2: Connect to OpenCode server
    stage_active("server")
    ai_client.ensure_server(function(server_err)
      if server_err then
        stage_error("server", server_err)
        return
      end
      stage_done("server")

      -- Step 3: Fetch PR info and diff in parallel
      stage_active("fetch")
      local pr_info_done = false
      local diff_done = false
      local pr_info_result = nil
      local diff_result = nil
      local had_error = false

      local function check_fetch_done()
        if not pr_info_done or not diff_done or had_error then return end

        session.set_pr_info(pr_info_result)
        session.set_diff(diff_result)

        local detail = string.format(
          "+%d -%d across %d files",
          pr_info_result.additions,
          pr_info_result.deletions,
          pr_info_result.changed_files
        )
        stage_done("fetch", detail)

        -- Re-render to show PR info in the loading panel
        refresh_loading()

        -- Step 4: Create OpenCode session
        stage_active("session")
        local session_title = string.format(
          "PR Review: %s/%s#%d - %s",
          owner, repo, number, pr_info_result.title
        )
        ai_client.create_session(session_title, function(_, session_err)
          if session_err then
            stage_error("session", session_err)
            return
          end
          stage_done("session")

          -- Step 5: AI review
          stage_active("review")
          ai_client.review_diff(diff_result, pr_info_result, function(review, review_err)
            if review_err then
              stage_error("review", review_err)
              return
            end

            -- Populate session (this flips loading->active)
            session.set_review(review)

            local stats = session.stats()
            stage_done("review", string.format("%d findings", stats.total))

            -- Transition to walkthrough
            transition_to_walkthrough()
          end)
        end)
      end

      github.fetch_pr_info(owner, repo, number, function(info, info_err)
        if info_err then
          if not had_error then
            stage_error("fetch", info_err)
          end
          had_error = true
          return
        end
        pr_info_result = info
        pr_info_done = true
        -- Update loading panel with PR info as soon as it arrives
        session.set_pr_info(info)
        refresh_loading()
        check_fetch_done()
      end)

      github.fetch_diff(owner, repo, number, function(diff, diff_err)
        if diff_err then
          if not had_error then
            stage_error("fetch", diff_err)
          end
          had_error = true
          return
        end
        diff_result = diff
        diff_done = true
        check_fetch_done()
      end)
    end)
  end)
end

---Start a review by showing a picker of open PRs.
---@param callback? fun() Called after user selects (review starts automatically)
function M.pick_pr(callback)
  vim.notify("[docent] Fetching open PRs...", vim.log.levels.INFO)

  github.fetch_open_prs(function(prs, err)
    if err then
      vim.notify("[docent] " .. err, vim.log.levels.ERROR)
      return
    end
    if not prs or #prs == 0 then
      vim.notify("[docent] No open PRs found in this repository", vim.log.levels.WARN)
      return
    end

    vim.ui.select(prs, {
      prompt = "Select a PR to review:",
      format_item = function(pr)
        return string.format("#%-5d  %-50s  (%s → %s)  @%s",
          pr.number,
          pr.title:sub(1, 50),
          pr.head,
          pr.base,
          pr.author
        )
      end,
    }, function(selected)
      if not selected then return end
      M.start(tostring(selected.number))
      if callback then callback() end
    end)
  end)
end

return M
