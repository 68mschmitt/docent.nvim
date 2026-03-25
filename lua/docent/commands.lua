local M = {}

-- A place for commands

function M.register()
    vim.api.nvim_create_user_command("DocentStartReview", function()
        require("docent.review.get").get_pull_request_list()
    end, { desc = "Start a Pull Request Review" })
end

return M
