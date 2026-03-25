local M = {}
local cfg = require("docent.config").get()

local function diff_file(diff)
    vim.cmd("tabnew")
    vim.cmd("vsplit")
    vim.cmd("read !git show origin/main:" .. diff)
    vim.cmd("0d_") -- remove extra blank line
    vim.cmd("diffthis")
    vim.cmd("wincmd l")
    vim.cmd("edit " .. diff)
    vim.cmd("diffthis")
end

local function diff_pr(pr_number)
  -- get changed files
  local files = vim.fn.systemlist(
    "gh pr diff " .. pr_number .. " --name-only"
  )

  for _, file in ipairs(files) do
    diff_file(file)
  end
end

function M.new_diff_view(pr_num)
    vim.fn.system(cfg.checkout_cli_command .. " " .. pr_num)

    diff_pr(pr_num)
end

return M
