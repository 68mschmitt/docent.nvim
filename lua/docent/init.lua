local M = {}

function M.setup(opts)
    require("docent.config").setup(opts);
    require("docent.commands").register();
end

return M
