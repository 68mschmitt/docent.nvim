local M = {}
local menu_utils = require("docent.menu.menu_utils")

local tmp_pr_command = "(cd ~/sc/compliance/onyx/core-compliance-api/ && gh pr list -q . --json number,author,title | jq)"

function M.present_options(pr_command)
    local pr_list = vim.fn.system(pr_command)

    if pr_list == nil then
        return
    end

    local decoded = vim.json.decode(pr_list)

    menu_utils.populate_selection_menu("Select a PR:", decoded)
end

return M

  -- additions
  -- assignees
  -- author
  -- autoMergeRequest
  -- baseRefName
  -- baseRefOid
  -- body
  -- changedFiles
  -- closed
  -- closedAt
  -- closingIssuesReferences
  -- comments
  -- commits
  -- createdAt
  -- deletions
  -- files
  -- fullDatabaseId
  -- headRefName
  -- headRefOid
  -- headRepository
  -- headRepositoryOwner
  -- id
  -- isCrossRepository
  -- isDraft
  -- labels
  -- latestReviews
  -- maintainerCanModify
  -- mergeCommit
  -- mergeStateStatus
  -- mergeable
  -- mergedAt
  -- mergedBy
  -- milestone
  -- number
  -- potentialMergeCommit
  -- projectCards
  -- projectItems
  -- reactionGroups
  -- reviewDecision
  -- reviewRequests
  -- reviews
  -- state
  -- statusCheckRollup
  -- title
  -- updatedAt
  -- url
  --
