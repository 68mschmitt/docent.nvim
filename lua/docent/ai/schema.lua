--- JSON schema definitions for OpenCode structured output.
local M = {}

---The JSON schema sent with the prompt to enforce structured findings output.
---@return table
function M.review_schema()
  return {
    type = "json_schema",
    schema = {
      type = "object",
      required = { "summary", "assessment", "findings" },
      properties = {
        summary = {
          type = "string",
          description = "2-3 sentence overview of what this PR does and its scope.",
        },
        assessment = {
          type = "string",
          description = "Overall assessment: is this PR ready to merge, what needs attention, and general quality impression.",
        },
        findings = {
          type = "array",
          description = "Ordered list of review findings. Order by severity: bug > warning > style > question > positive > info.",
          items = {
            type = "object",
            required = { "category", "title", "file", "line", "explanation", "learning" },
            properties = {
              category = {
                type = "string",
                enum = { "bug", "warning", "style", "question", "positive", "info" },
                description = "Finding category: bug (likely defect), warning (potential issue), style (readability/naming), question (unclear intent), positive (good pattern worth noting), info (context about a complex change).",
              },
              title = {
                type = "string",
                description = "Short descriptive title, max 60 characters. Should be scannable in a list.",
              },
              file = {
                type = "string",
                description = "Relative file path where the finding applies.",
              },
              line = {
                type = "integer",
                description = "Primary line number in the new file where the finding applies.",
              },
              end_line = {
                type = "integer",
                description = "End line number if the finding spans multiple lines. Omit if single line.",
              },
              explanation = {
                type = "string",
                description = "WHAT: What this change does and WHY IT MATTERS. Be specific about the impact. Reference exact line numbers and variable names.",
              },
              learning = {
                type = "string",
                description = "LEARNING: The underlying principle, pattern, or concept to take away. Connect this specific finding to a broader transferable lesson. Think: what would a senior engineer want a mid-level engineer to internalize from seeing this?",
              },
              suggestion = {
                type = "string",
                description = "SUGGESTION: A concrete, actionable suggestion for improvement. Include code snippets if helpful. Omit if the finding is purely informational or positive.",
              },
            },
          },
        },
      },
    },
  }
end

---Schema for follow-up question responses (free-form text, no structure enforced).
---Follow-ups use the same session and return plain text in the message parts.
---@return nil
function M.followup_schema()
  return nil
end

return M
