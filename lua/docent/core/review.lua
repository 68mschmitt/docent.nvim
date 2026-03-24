--- Review orchestrator.
--- Coordinates the full review pipeline:
--- connect to OpenCode -> fetch PR -> fetch diff -> AI review -> open walkthrough.
local ai_client = require("docent.ai.client")
local github = require("docent.github")
local session = require("docent.core.session")
local walkthrough = require("docent.layout.walkthrough")

local M = {}

---Start a review for a PR reference.
---@param pr_ref string PR reference (#123, owner/repo#123, or URL)
function M.start(pr_ref)
  -- Reset any existing session and shut down old AI client
  if session.is_active() then
    walkthrough.close()
  end
  session.reset()

  -- Step 0: Parse the PR reference (async for bare numbers)
  vim.notify("[docent] Resolving PR reference...", vim.log.levels.INFO)
  github.parse_pr_ref(pr_ref, function(owner, repo, number, parse_err)
    if parse_err then
      vim.notify("[docent] " .. parse_err, vim.log.levels.ERROR)
      return
    end

    vim.notify("[docent] Starting review for " .. owner .. "/" .. repo .. "#" .. number .. "...", vim.log.levels.INFO)

    -- Step 1: Ensure OpenCode server is running
    vim.notify("[docent] Connecting to OpenCode server...", vim.log.levels.INFO)
    ai_client.ensure_server(function(server_err)
      if server_err then
        vim.notify("[docent] " .. server_err, vim.log.levels.ERROR)
        return
      end

      -- Step 2: Fetch PR info and diff in parallel
      vim.notify("[docent] Fetching PR data...", vim.log.levels.INFO)
      local pr_info_done = false
      local diff_done = false
      local pr_info_result = nil
      local diff_result = nil
      local had_error = false

      local function check_both_done()
        if not pr_info_done or not diff_done or had_error then return end

        session.set_pr_info(pr_info_result)
        session.set_diff(diff_result)

        -- Step 3: Create OpenCode session
        local session_title = string.format("PR Review: %s/%s#%d", owner, repo, number)
        ai_client.create_session(session_title, function(_, session_err)
          if session_err then
            vim.notify("[docent] Failed to create session: " .. session_err, vim.log.levels.ERROR)
            return
          end

          -- Step 4: Send diff for AI review
          vim.notify("[docent] AI is reviewing the PR... (this may take a minute)", vim.log.levels.INFO)
          ai_client.review_diff(diff_result, pr_info_result, function(review, review_err)
            if review_err then
              vim.notify("[docent] AI review failed: " .. review_err, vim.log.levels.ERROR)
              return
            end

            -- Step 5: Populate session and open walkthrough
            session.set_review(review)

            local stats = session.stats()
            vim.notify(
              string.format("[docent] Review complete: %d findings. Opening walkthrough...", stats.total),
              vim.log.levels.INFO
            )

            walkthrough.open()
          end)
        end)
      end

      github.fetch_pr_info(owner, repo, number, function(info, info_err)
        if info_err then
          if not had_error then
            vim.notify("[docent] " .. info_err, vim.log.levels.ERROR)
          end
          had_error = true
          return
        end
        pr_info_result = info
        pr_info_done = true
        check_both_done()
      end)

      github.fetch_diff(owner, repo, number, function(diff, diff_err)
        if diff_err then
          if not had_error then
            vim.notify("[docent] " .. diff_err, vim.log.levels.ERROR)
          end
          had_error = true
          return
        end
        diff_result = diff
        diff_done = true
        check_both_done()
      end)
    end)
  end)
end

return M
