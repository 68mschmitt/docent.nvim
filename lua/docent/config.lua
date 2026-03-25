local M = {}

local default_config = {
    -- A place for configs
    cli_command = "gh pr list",
    checkout_cli_command = "gh pr checkout",
    cli_command_options = "-q . --json",
    cli_command_json_fields = {
        "number",
        "author",
        "title",
    },
}

local config = {}

function M.setup(opts)
    -- Setup the config
    config = default_config

    config.pr_cli_command =
        config.cli_command .. " " ..
        config.cli_command_options .. " " ..
        table.concat(config.cli_command_json_fields, ",") -- Flatten the list of fields
end

function M.get()
    return config
end

return M
