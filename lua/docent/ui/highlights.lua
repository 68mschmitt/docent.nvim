--- Highlight groups and sign definitions for docent.
local M = {}

---Define all highlight groups. Called once during setup.
function M.setup()
  local groups = {
    -- Finding categories
    DocentBug          = { fg = "#e06c75", bold = true },
    DocentWarning      = { fg = "#e5c07b", bold = true },
    DocentStyle        = { fg = "#6b7280" },
    DocentQuestion     = { fg = "#61afef" },
    DocentPositive     = { fg = "#98c379", bold = true },
    DocentInfo         = { fg = "#56b6c2" },

    -- Finding statuses
    DocentPending      = { fg = "#abb2bf" },
    DocentAcknowledged = { fg = "#98c379" },
    DocentDismissed    = { fg = "#6b7280", strikethrough = true },

    -- Current finding indicator
    DocentCurrent      = { fg = "#c678dd", bold = true },

    -- Panel headers
    DocentHeader       = { fg = "#abb2bf", bold = true, underline = true },
    DocentHeaderAccent = { fg = "#61afef", bold = true },

    -- Keymap hints in panel footers
    DocentKeyHint      = { fg = "#6b7280" },
    DocentKey          = { fg = "#e5c07b" },

    -- Note panel sections
    DocentNoteSection  = { fg = "#c678dd", bold = true },
    DocentNoteText     = { fg = "#abb2bf" },

    -- Chat panel
    DocentChatUser     = { fg = "#61afef", bold = true },
    DocentChatAI       = { fg = "#98c379" },

    -- Diff
    DocentDiffAdd      = { fg = "#98c379" },
    DocentDiffDel      = { fg = "#e06c75" },
    DocentDiffHunk     = { fg = "#c678dd" },
    DocentDiffFile     = { fg = "#61afef", bold = true },

    -- Active finding highlight in diff (the lines the current note refers to)
    DocentDiffFocusLine  = { bg = "#2a2e36", bold = true },
    DocentDiffFocusAdd   = { fg = "#98c379", bg = "#2a2e36", bold = true },
    DocentDiffFocusDel   = { fg = "#e06c75", bg = "#2a2e36", bold = true },

    -- Other findings in the same file (subtle gutter + underline)
    DocentDiffOtherMark  = { sp = "#6b7280", underline = true },

    -- Signs (gutter markers for findings in diff view)
    DocentSignBug      = { fg = "#e06c75" },
    DocentSignWarning  = { fg = "#e5c07b" },
    DocentSignStyle    = { fg = "#6b7280" },
    DocentSignQuestion = { fg = "#61afef" },
    DocentSignPositive = { fg = "#98c379" },
    DocentSignInfo     = { fg = "#56b6c2" },

    -- Status line components
    DocentStatusActive = { fg = "#98c379", bold = true },
    DocentStatusCount  = { fg = "#e5c07b" },

    -- Loading / progress
    DocentLoading      = { fg = "#6b7280", italic = true },
  }

  for name, opts in pairs(groups) do
    -- Use default=true so user colorscheme overrides take precedence
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  -- Define signs for gutter markers in the full diff view
  local signs = {
    { name = "DocentBugSign",      text = "!!", texthl = "DocentSignBug" },
    { name = "DocentWarningSign",  text = "! ", texthl = "DocentSignWarning" },
    { name = "DocentStyleSign",    text = "~ ", texthl = "DocentSignStyle" },
    { name = "DocentQuestionSign", text = "? ", texthl = "DocentSignQuestion" },
    { name = "DocentPositiveSign", text = "+ ", texthl = "DocentSignPositive" },
    { name = "DocentInfoSign",     text = "i ", texthl = "DocentSignInfo" },
  }

  for _, sign in ipairs(signs) do
    vim.fn.sign_define(sign.name, {
      text = sign.text,
      texthl = sign.texthl,
    })
  end
end

---Get the sign name for a finding category.
---@param category docent.FindingCategory
---@return string
function M.sign_for_category(category)
  local map = {
    bug = "DocentBugSign",
    warning = "DocentWarningSign",
    style = "DocentStyleSign",
    question = "DocentQuestionSign",
    positive = "DocentPositiveSign",
    info = "DocentInfoSign",
  }
  return map[category] or "DocentInfoSign"
end

return M
