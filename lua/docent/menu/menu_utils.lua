local M = {}

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
                vim.notify("You chose " .. choice.author.name .. "!")
            end
        end)
end

return M
