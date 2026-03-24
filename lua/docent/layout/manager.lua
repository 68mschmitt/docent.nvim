--- Layout manager.
--- Creates and manages the three-panel walkthrough layout.
--- Handles window creation, guarding against accidental closes, and teardown.
local config = require("docent.config")
local findings_list = require("docent.ui.findings_list")
local diff_view = require("docent.ui.diff_view")
local note_panel = require("docent.ui.note_panel")

local M = {}

---@class docent.LayoutState
---@field tab number|nil The tab page used for the walkthrough
---@field findings_win number|nil
---@field diff_win number|nil
---@field note_win number|nil
---@field augroup number|nil Autocommand group for layout guards
---@field is_open boolean

---@type docent.LayoutState
local state = {
  tab = nil,
  findings_win = nil,
  diff_win = nil,
  note_win = nil,
  augroup = nil,
  is_open = false,
}

---Check if the layout is currently open.
---@return boolean
function M.is_open()
  return state.is_open
end

---Open the three-panel layout in a new tab.
---@return boolean success
function M.open()
  if state.is_open then
    -- Switch to existing tab
    if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
      vim.api.nvim_set_current_tabpage(state.tab)
    end
    return true
  end

  local cfg = config.get()

  -- Create buffers first
  local findings_buf = findings_list.create()
  local diff_buf = diff_view.create()
  local note_buf = note_panel.create()

  -- Open a new tab for the walkthrough
  vim.cmd("tabnew")
  state.tab = vim.api.nvim_get_current_tabpage()

  -- The new tab starts with one window. Use it for the diff (largest panel).
  state.diff_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.diff_win, diff_buf)

  -- Create findings list to the left
  vim.cmd("topleft vsplit")
  state.findings_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.findings_win, findings_buf)
  vim.api.nvim_win_set_width(state.findings_win, cfg.layout.finding_list_width)

  -- Create note panel at the bottom (spans full width)
  -- Go back to diff window first, then split below
  vim.api.nvim_set_current_win(state.diff_win)
  vim.cmd("botright split")
  state.note_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.note_win, note_buf)
  vim.api.nvim_win_set_height(state.note_win, cfg.layout.note_panel_height)

  -- Configure window options for all panels
  for _, win in ipairs({ state.findings_win, state.diff_win, state.note_win }) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = "yes"
      vim.wo[win].wrap = true
      vim.wo[win].cursorline = false
      vim.wo[win].foldcolumn = "0"
      vim.wo[win].spell = false
      vim.wo[win].list = false
    end
  end

  -- Fix widths/heights to prevent resizing
  vim.wo[state.findings_win].winfixwidth = true
  vim.wo[state.note_win].winfixheight = true
  vim.wo[state.findings_win].signcolumn = "no"
  vim.wo[state.note_win].signcolumn = "no"

  -- Set up layout guards (autocmds to handle accidental window closes)
  M.setup_guards()

  -- Focus the findings list
  vim.api.nvim_set_current_win(state.findings_win)

  state.is_open = true
  return true
end

---Close the layout and clean up everything.
function M.close()
  if not state.is_open then return end

  -- Remove guard autocmds
  if state.augroup then
    vim.api.nvim_del_augroup_by_id(state.augroup)
    state.augroup = nil
  end

  -- Destroy panel buffers/windows
  note_panel.destroy()
  diff_view.destroy()
  findings_list.destroy()

  -- Close the tab if it's still valid and not the last tab
  if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
    local tabs = vim.api.nvim_list_tabpages()
    if #tabs > 1 then
      -- Switch to another tab first, then close ours
      for _, t in ipairs(tabs) do
        if t ~= state.tab then
          vim.api.nvim_set_current_tabpage(t)
          break
        end
      end
      pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(state.tab))
    end
  end

  state = {
    tab = nil,
    findings_win = nil,
    diff_win = nil,
    note_win = nil,
    augroup = nil,
    is_open = false,
  }
end

---Set up autocmds that guard against broken layout.
function M.setup_guards()
  state.augroup = vim.api.nvim_create_augroup("DocentLayout", { clear = true })

  -- When a window is closed, check if it was one of ours
  vim.api.nvim_create_autocmd("WinClosed", {
    group = state.augroup,
    callback = function(ev)
      if not state.is_open then return end

      local closed_win = tonumber(ev.match)
      local our_wins = { state.findings_win, state.diff_win, state.note_win }

      local is_ours = false
      for _, w in ipairs(our_wins) do
        if w == closed_win then
          is_ours = true
          break
        end
      end

      if is_ours then
        -- One of our windows was closed -- close the entire layout
        vim.schedule(function()
          M.close()
        end)
      end
    end,
  })

  -- When leaving the tab, nothing special needed
  -- When entering the tab, re-validate windows
  vim.api.nvim_create_autocmd("TabEnter", {
    group = state.augroup,
    callback = function()
      if not state.is_open then return end
      if vim.api.nvim_get_current_tabpage() ~= state.tab then return end

      -- Validate all windows still exist
      local valid = true
      for _, w in ipairs({ state.findings_win, state.diff_win, state.note_win }) do
        if not w or not vim.api.nvim_win_is_valid(w) then
          valid = false
          break
        end
      end

      if not valid then
        vim.schedule(function()
          M.close()
          vim.notify("[docent] Layout was corrupted. Review closed.", vim.log.levels.WARN)
        end)
      end
    end,
  })
end

---Get the layout state (for use by walkthrough).
---@return docent.LayoutState
function M.get_state()
  return state
end

---Focus a specific panel.
---@param panel "findings"|"diff"|"note"
function M.focus(panel)
  local win_map = {
    findings = state.findings_win,
    diff = state.diff_win,
    note = state.note_win,
  }
  local win = win_map[panel]
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

return M
