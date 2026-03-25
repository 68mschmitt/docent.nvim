local M = {}

local default_config = {
    -- A place for configs
    cli_command = "gh pr list",
    cli_command_options = "-q . --json",
    cli_command_json_fields = {
        "number",
        "author",
        "title",
    },
    testing = true
}

local config = {}

function M.setup(opts)
    -- Setup the config
    config = default_config

    config.pr_cli_command =
        config.cli_command .. " " ..
        config.cli_command_options .. " " ..
        table.concat(config.cli_command_json_fields, ",") -- Flatten the list of fields

    if config.testing then
        local tmp_pr_command = "(cd ~/sc/compliance/onyx/core-compliance-api/ && ".. config.pr_cli_command ..")"
        config.pr_cli_command = tmp_pr_command
    end
end

function M.get()
    return config
end

return M
