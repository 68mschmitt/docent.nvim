local M = {}
local diff_view = require("docent.review.diff_view")

local function format_pr_option(item)
    local author_name = item.author.login
    if item.author.is_bot == false then
        author_name = item.author.name
    end
    return "#" .. item.number .. ": " .. author_name .. " - " .. item.title
end

function M.populate_selection_menu(prompt, options)
    if options == nil then
        vim.notify("There werent any PRs to choose from")
        return
    end

    vim.ui.select(
        options,
        {
            prompt = prompt,
            format_item = format_pr_option,
        },
        function(choice)
            if choice ~= nil then
                vim.notify("Checked out branch for PR #" .. choice.number .. "!")
                diff_view.new_diff_view(choice.number)
            end
        end)
end

return M
