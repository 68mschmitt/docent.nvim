--- docent.nvim - AI-guided PR review walkthrough for Neovim.
---
--- A neovim plugin that runs an AI-powered PR review via OpenCode and presents
--- findings as a structured, navigable walkthrough. Three synced panels:
--- findings list, diff view, and explanation note. Each finding teaches the
--- what, why, and underlying principle.
---
--- Requires: plenary.nvim, gh CLI, OpenCode (opencode serve)
local config = require("docent.config")
local highlights = require("docent.ui.highlights")

local M = {}

---Setup docent with user configuration.
---@param opts? table User configuration overrides
function M.setup(opts)
  config.setup(opts)
  highlights.setup()
  M.create_commands()
end

---Create all user commands.
function M.create_commands()
  vim.api.nvim_create_user_command("DocentReview", function(cmd_opts)
    local pr_ref = cmd_opts.args
    local review = require("docent.core.review")

    if not pr_ref or pr_ref == "" then
      -- No argument: open PR picker
      review.pick_pr()
    else
      -- Argument given: start review directly
      review.start(pr_ref)
    end
  end, {
    nargs = "?",
    desc = "Start an AI-guided PR review walkthrough (no args = pick from open PRs)",
    complete = function()
      return {}
    end,
  })

  vim.api.nvim_create_user_command("DocentSummary", function()
    require("docent.layout.summary").open()
  end, {
    desc = "Show review summary",
  })

  vim.api.nvim_create_user_command("DocentDiff", function()
    require("docent.layout.fulldiff").open()
  end, {
    desc = "Show full diff with finding markers",
  })

  vim.api.nvim_create_user_command("DocentApprove", function()
    require("docent.layout.walkthrough").approve()
  end, {
    desc = "Approve the PR",
  })

  vim.api.nvim_create_user_command("DocentRequestChanges", function()
    require("docent.layout.walkthrough").request_changes()
  end, {
    desc = "Request changes on the PR",
  })

  vim.api.nvim_create_user_command("DocentClose", function()
    require("docent.layout.walkthrough").close()
  end, {
    desc = "Close the review walkthrough",
  })

  vim.api.nvim_create_user_command("DocentAttach", function()
    local ai_client = require("docent.ai.client")
    local cfg = config.get()
    local server_url = ai_client.get_server_url()
    local session_id = ai_client.get_session_id()

    if not server_url then
      vim.notify("[docent] No OpenCode server connection. Start a review first.", vim.log.levels.WARN)
      return
    end

    local cmd = cfg.opencode_cmd .. " attach " .. server_url
    if session_id then
      cmd = cmd .. " --session " .. session_id
    end

    -- Open in a vertical split with a terminal buffer
    vim.cmd("vsplit")
    vim.fn.termopen(cmd, {
      on_exit = function()
        vim.schedule(function()
          local buf = vim.api.nvim_get_current_buf()
          if vim.bo[buf].buftype == "terminal" then
            vim.cmd("bdelete!")
          end
        end)
      end,
    })
    vim.cmd("startinsert")
  end, {
    desc = "Attach to the OpenCode session to watch the AI review in real-time",
  })
end

return M
