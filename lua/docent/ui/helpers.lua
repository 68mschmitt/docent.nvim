--- Shared UI helpers: header rendering, footer keymap hints, input prompts.
local config = require("docent.config")

local M = {}

---Get the display width of a string (handles multi-byte UTF-8 correctly).
---@param s string
---@return number
local function display_width(s)
  return vim.api.nvim_strwidth(s)
end

---Render a header line for a panel buffer.
---Centers the title text and pads with the fill character.
---@param title string The header text
---@param width number Available width in columns
---@param fill? string Fill character (default "─")
---@return string
function M.header(title, width, fill)
  fill = fill or "─"
  local padded = " " .. title .. " "
  local remaining = width - display_width(padded)
  if remaining <= 0 then return padded end
  local left = math.floor(remaining / 2)
  local right = remaining - left
  return string.rep(fill, left) .. padded .. string.rep(fill, right)
end

---Render a left-aligned header: "─ Title ────────────────"
---@param title string
---@param width number
---@return string
function M.header_left(title, width)
  local padded = "─ " .. title .. " "
  local remaining = width - display_width(padded)
  if remaining <= 0 then return padded end
  return padded .. string.rep("─", remaining)
end

---Build a keymap hint line for a panel footer.
---@param hints {key: string, desc: string}[]
---@param width number Available width
---@return string
function M.footer_hints(hints, width)
  if not config.get().show_keymaps then
    return ""
  end
  local parts = {}
  for _, h in ipairs(hints) do
    table.insert(parts, h.key .. " " .. h.desc)
  end
  local text = table.concat(parts, "  ")
  if display_width(text) > width then
    text = text:sub(1, width - 1) .. "…"
  end
  return text
end

---Set highlight ranges on a buffer line for keymap hints.
---Keys are highlighted with DocentKey, descriptions with DocentKeyHint.
---Uses byte offsets for the highlight API.
---@param buf number Buffer handle
---@param line_nr number 0-indexed line number
---@param hints {key: string, desc: string}[]
function M.apply_footer_highlights(buf, line_nr, hints)
  local col = 0
  for i, h in ipairs(hints) do
    -- Highlight the key (byte offsets for nvim_buf_add_highlight)
    pcall(vim.api.nvim_buf_add_highlight, buf, -1, "DocentKey", line_nr, col, col + #h.key)
    col = col + #h.key
    -- Space separator
    col = col + 1
    -- Highlight the description
    pcall(vim.api.nvim_buf_add_highlight, buf, -1, "DocentKeyHint", line_nr, col, col + #h.desc)
    col = col + #h.desc
    -- Double space separator between hints
    if i < #hints then
      col = col + 2
    end
  end
end

---Open a single-line input prompt at the bottom of the screen.
---@param prompt_text string The prompt label
---@param callback fun(input: string|nil) Called with input text, or nil if cancelled
function M.input(prompt_text, callback)
  vim.ui.input({ prompt = prompt_text .. ": " }, function(input)
    if input and input ~= "" then
      callback(input)
    else
      callback(nil)
    end
  end)
end

---Wrap text to a given width, respecting word boundaries.
---Preserves blank lines in the input.
---@param text string
---@param width number
---@return string[]
function M.wrap_text(text, width)
  local lines = {}

  -- Split on newlines, preserving empty lines
  local paragraphs = vim.split(text, "\n", { plain = true })

  for _, paragraph in ipairs(paragraphs) do
    if paragraph == "" or paragraph:match("^%s*$") then
      -- Preserve blank lines
      table.insert(lines, "")
    else
      local line = ""
      for word in paragraph:gmatch("%S+") do
        if display_width(line) + display_width(word) + 1 > width then
          if line ~= "" then
            table.insert(lines, line)
          end
          line = word
        elseif line == "" then
          line = word
        else
          line = line .. " " .. word
        end
      end
      if line ~= "" then
        table.insert(lines, line)
      end
    end
  end

  if #lines == 0 then
    table.insert(lines, "")
  end
  return lines
end

---Create a scratch buffer with standard docent options.
---Uses a unique suffix to avoid name collisions.
---@param name string Buffer name
---@return number buf Buffer handle
function M.create_buf(name)
  local buf = vim.api.nvim_create_buf(false, true)
  -- Use a unique name to avoid collisions with previous sessions
  local unique_name = string.format("docent://%s/%d", name, buf)
  pcall(vim.api.nvim_buf_set_name, buf, unique_name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide" -- "hide" instead of "wipe" to survive tab switches
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "docent"
  return buf
end

---Set lines on a nomodifiable buffer.
---@param buf number
---@param lines string[]
function M.set_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

return M
