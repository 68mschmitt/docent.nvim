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
    desc = "Close the review and restore original branch",
  })

  vim.api.nvim_create_user_command("DocentHide", function()
    require("docent.layout.walkthrough").hide()
  end, {
    desc = "Hide the review layout (keeps session alive)",
  })

  vim.api.nvim_create_user_command("DocentResume", function()
    local walkthrough = require("docent.layout.walkthrough")
    local session = require("docent.core.session")
    if session.is_active() then
      walkthrough.resume()
    else
      -- Try loading the last saved review for this repo
      local saved = require("docent.core.storage")
      local data = saved.load_latest()
      if data then
        session.deserialize(data)
        walkthrough.resume()
      else
        vim.notify("[docent] No active or saved review to resume.", vim.log.levels.WARN)
      end
    end
  end, {
    desc = "Resume a hidden or saved review",
  })

  vim.api.nvim_create_user_command("DocentSave", function()
    local session = require("docent.core.session")
    local storage = require("docent.core.storage")
    local data = session.serialize()
    if not data then
      vim.notify("[docent] No active review to save.", vim.log.levels.WARN)
      return
    end
    local path, err = storage.save(data)
    if err then
      vim.notify("[docent] " .. err, vim.log.levels.ERROR)
    else
      vim.notify("[docent] Review saved to " .. path, vim.log.levels.INFO)
    end
  end, {
    desc = "Save the current review to disk",
  })

  vim.api.nvim_create_user_command("DocentLoad", function(cmd_opts)
    local storage = require("docent.core.storage")
    local session = require("docent.core.session")
    local walkthrough = require("docent.layout.walkthrough")

    local file = cmd_opts.args
    if not file or file == "" then
      -- Pick from saved reviews
      local files = storage.list_saved()
      if #files == 0 then
        vim.notify("[docent] No saved reviews found.", vim.log.levels.WARN)
        return
      end
      vim.ui.select(files, {
        prompt = "Select a saved review:",
        format_item = function(f)
          return vim.fn.fnamemodify(f, ":t:r") -- show filename without extension
        end,
      }, function(selected)
        if not selected then return end
        local data, err = storage.load(selected)
        if err then
          vim.notify("[docent] " .. err, vim.log.levels.ERROR)
          return
        end
        if session.deserialize(data) then
          walkthrough.resume()
        else
          vim.notify("[docent] Failed to load review: invalid data", vim.log.levels.ERROR)
        end
      end)
    else
      local data, err = storage.load(file)
      if err then
        vim.notify("[docent] " .. err, vim.log.levels.ERROR)
        return
      end
      if session.deserialize(data) then
        walkthrough.resume()
      else
        vim.notify("[docent] Failed to load review: invalid data", vim.log.levels.ERROR)
      end
    end
  end, {
    nargs = "?",
    desc = "Load a saved review from disk",
    complete = function()
      local storage = require("docent.core.storage")
      local files = storage.list_saved()
      local names = {}
      for _, f in ipairs(files) do
        table.insert(names, f)
      end
      return names
    end,
  })

  vim.api.nvim_create_user_command("DocentAttach", function()
    local ai_client = require("docent.ai.client")
    local diff_view = require("docent.ui.diff_view")
    local layout = require("docent.layout.manager")
    local cfg = config.get()
    local server_url = ai_client.get_server_url()
    local session_id = ai_client.get_session_id()

    if not server_url then
      vim.notify("[docent] No OpenCode server connection. Start a review first.", vim.log.levels.WARN)
      return
    end

    if not layout.is_open() then
      vim.notify("[docent] No docent layout open. Start a review first.", vim.log.levels.WARN)
      return
    end

    -- Toggle: if terminal is already showing, close it and render the diff
    if diff_view.is_terminal_open() then
      diff_view.close_terminal()
      diff_view.render()
      return
    end

    -- Open the terminal in the diff panel
    local cmd = cfg.opencode_cmd .. " attach " .. server_url
    if session_id then
      cmd = cmd .. " --session " .. session_id
    end
    diff_view.open_terminal(cmd)
  end, {
    desc = "Toggle the OpenCode session in the diff panel",
  })
end

return M
