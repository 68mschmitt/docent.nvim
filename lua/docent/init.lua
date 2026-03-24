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
    if not pr_ref or pr_ref == "" then
      vim.notify("[docent] Usage: :DocentReview <pr-ref>  (e.g., #123, owner/repo#123, or URL)", vim.log.levels.WARN)
      return
    end
    require("docent.core.review").start(pr_ref)
  end, {
    nargs = 1,
    desc = "Start an AI-guided PR review walkthrough",
    complete = function()
      -- Could add completion for open PRs in the future
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
end

return M
