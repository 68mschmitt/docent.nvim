local M = {}

---@class docent.Config
---@field opencode_url string|nil Base URL for the OpenCode server (nil = auto-detect)
---@field opencode_cmd string Path to the opencode binary (for auto-start)
---@field opencode_port number Port for auto-started opencode server
---@field gh_cmd string Path to the gh CLI binary
---@field layout docent.LayoutConfig
---@field show_keymaps boolean Show keymap hints in panel footers
---@field review_prompt string System prompt prefix for AI review
---@field model? {providerID: string, modelID: string} Model override

---@class docent.LayoutConfig
---@field finding_list_width number Width of the findings list panel in columns
---@field note_panel_height number Height of the note panel in lines
---@field chat_panel_width number Width of the chat panel when note splits (percentage 0-100)

---@type docent.Config
M.defaults = {
  opencode_url = nil, -- nil = auto-detect or start server
  opencode_cmd = "opencode",
  opencode_port = 19847,
  gh_cmd = "gh",
  layout = {
    finding_list_width = 34,
    note_panel_height = 12,
    chat_panel_width = 50, -- percentage of note panel width
  },
  show_keymaps = true,
  review_prompt = table.concat({
    "You are a senior code reviewer and mentor.",
    "Review the following PR diff thoroughly and comprehensively.",
    "For each finding, explain WHAT the change does, WHY IT MATTERS,",
    "provide a LEARNING that connects it to a broader principle or pattern,",
    "and a concrete SUGGESTION if applicable.",
    "Cover bugs, logic errors, security issues, performance concerns,",
    "style/readability, good patterns worth noting, and any questions",
    "about unclear intent.",
    "Be specific: reference exact line numbers and variable names.",
    "Order findings by severity: bugs first, then warnings, then style,",
    "then questions, then positive callouts, then informational notes.",
  }, " "),
  model = nil,
}

---@type docent.Config
M.current = vim.deepcopy(M.defaults)

---Merge user config with defaults
---@param opts? table
function M.setup(opts)
  M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

---Get the current config
---@return docent.Config
function M.get()
  return M.current
end

return M
