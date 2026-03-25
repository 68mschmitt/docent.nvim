local M = {}

-- A place for commands

function M.register()
    vim.api.nvim_create_user_command("DocentStartReview", function()
        local cfg = require("docent.config").get()
        require("docent.review.pr_options").present_options(cfg.pr_cli_command)
    end, { desc = "Start a Pull Request Review" })
end

return M
