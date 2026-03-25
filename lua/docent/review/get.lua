local M = {}

local tmp_pr_command = "(cd ~/sc/compliance/onyx/core-compliance-api/ && gh pr list -q . --json number,author,title | jq)"

local function format_pr_option(item)
    local author_name = item.author.login
    if item.author.is_bot == false then
        author_name = item.author.name
    end
    return "#" .. item.number .. ": " .. author_name .. " - " .. item.title
end

local function testing_menu(options)
    if options == nil then
        vim.notify("There werent any PRs to choose from")
        return
    end

    local prompt = "Select a PR:"

    vim.ui.select(
        options,
        {
            prompt = prompt,
            format_item = format_pr_option,
        },
        function(choice)
            if choice ~= nil then
                vim.notify("You chose " .. choice.author.name .. "!")
            end
        end)
end

function M.get_pr_list()
    local pr_list = vim.fn.system(tmp_pr_command)

    if pr_list == nil then
        return
    end

    local decoded = vim.json.decode(pr_list)

    testing_menu(decoded)
end

M.get_pr_list()

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
