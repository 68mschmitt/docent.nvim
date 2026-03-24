--- HTTP client for OpenCode server API.
--- Manages server connection, sessions, and structured prompts.
local curl = require("plenary.curl")
local config = require("docent.config")
local schema = require("docent.ai.schema")

local M = {}

---@class docent.AIState
---@field server_url string|nil Resolved server URL
---@field session_id string|nil Current OpenCode session ID
---@field server_job number|nil Job ID if we auto-started the server
local state = {
  server_url = nil,
  session_id = nil,
  server_job = nil,
}

---Build the full URL for an API endpoint.
---@param path string
---@return string
local function url(path)
  return state.server_url .. path
end

---Make a synchronous GET request.
---@param path string
---@return table|nil response
---@return string|nil error
local function get(path)
  local ok, response = pcall(curl.get, url(path), {
    headers = { ["Content-Type"] = "application/json" },
    timeout = 10000,
  })
  if not ok then
    return nil, "HTTP request failed: " .. tostring(response)
  end
  if response.status ~= 200 then
    return nil, string.format("HTTP %d: %s", response.status, response.body or "")
  end
  local decoded = vim.json.decode(response.body)
  return decoded, nil
end

---Make a synchronous POST request with a JSON body.
---@param path string
---@param body table
---@param timeout? number Timeout in ms (default 120000 for AI calls)
---@return table|nil response
---@return string|nil error
local function post(path, body, timeout)
  local ok, response = pcall(curl.post, url(path), {
    headers = { ["Content-Type"] = "application/json" },
    body = vim.json.encode(body),
    timeout = timeout or 120000,
  })
  if not ok then
    return nil, "HTTP request failed: " .. tostring(response)
  end
  if response.status ~= 200 and response.status ~= 204 then
    return nil, string.format("HTTP %d: %s", response.status, response.body or "")
  end
  if response.body and #response.body > 0 then
    local decoded = vim.json.decode(response.body)
    return decoded, nil
  end
  return {}, nil
end

---Make an async POST request with a JSON body (non-blocking).
---@param path string
---@param body table
---@param callback fun(response: table|nil, err: string|nil)
---@param timeout? number
local function post_async(path, body, callback, timeout)
  curl.post(url(path), {
    headers = { ["Content-Type"] = "application/json" },
    body = vim.json.encode(body),
    timeout = timeout or 180000,
    callback = function(response)
      vim.schedule(function()
        if response.status ~= 200 and response.status ~= 204 then
          callback(nil, string.format("HTTP %d: %s", response.status, response.body or ""))
          return
        end
        if response.body and #response.body > 0 then
          local ok, decoded = pcall(vim.json.decode, response.body)
          if ok then
            callback(decoded, nil)
          else
            callback(nil, "Failed to parse response JSON: " .. tostring(decoded))
          end
        else
          callback({}, nil)
        end
      end)
    end,
  })
end

---Check if the OpenCode server is reachable.
---@return boolean
function M.is_server_running()
  if not state.server_url then
    return false
  end
  local resp, err = get("/global/health")
  return err == nil and resp ~= nil and resp.healthy == true
end

---Auto-start the OpenCode server if not running.
---@param callback fun(err: string|nil)
function M.ensure_server(callback)
  local cfg = config.get()

  -- If a URL is explicitly configured, use it directly
  if cfg.opencode_url then
    state.server_url = cfg.opencode_url
    if M.is_server_running() then
      callback(nil)
    else
      callback("OpenCode server not reachable at " .. cfg.opencode_url)
    end
    return
  end

  -- Try default port first
  state.server_url = string.format("http://127.0.0.1:%d", cfg.opencode_port)
  if M.is_server_running() then
    callback(nil)
    return
  end

  -- Auto-start the server in the current working directory
  local cwd = vim.fn.getcwd()
  local cmd = { cfg.opencode_cmd, "serve", "--port", tostring(cfg.opencode_port) }
  state.server_job = vim.fn.jobstart(cmd, {
    cwd = cwd,
    detach = true,
    on_stderr = function(_, data)
      if data and data[1] and data[1] ~= "" then
        vim.schedule(function()
          vim.notify("[docent] opencode server: " .. table.concat(data, "\n"), vim.log.levels.DEBUG)
        end)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("[docent] opencode server exited with code " .. code, vim.log.levels.ERROR)
        end)
      end
      state.server_job = nil
    end,
  })

  -- Poll until server is ready (up to 15 seconds)
  local attempts = 0
  local max_attempts = 30
  local timer = vim.uv.new_timer()
  timer:start(
    500,
    500,
    vim.schedule_wrap(function()
      attempts = attempts + 1
      if M.is_server_running() then
        timer:stop()
        timer:close()
        callback(nil)
      elseif attempts >= max_attempts then
        timer:stop()
        timer:close()
        callback("Timed out waiting for OpenCode server to start")
      end
    end)
  )
end

---Create a new OpenCode session for a review.
---@param title string
---@param callback fun(session_id: string|nil, err: string|nil)
function M.create_session(title, callback)
  post_async("/session", { title = title }, function(resp, err)
    if err then
      callback(nil, err)
      return
    end
    -- The response contains the session object with an id field
    local id = resp.id or (resp.data and resp.data.id)
    if not id then
      callback(nil, "No session ID in response: " .. vim.inspect(resp))
      return
    end
    state.session_id = id
    callback(id, nil)
  end)
end

---Send the PR diff for AI review with structured output.
---@param diff_text string The unified diff content
---@param pr_info {owner: string, repo: string, number: number, title: string}
---@param callback fun(review: docent.ReviewResult|nil, err: string|nil)
function M.review_diff(diff_text, pr_info, callback)
  if not state.session_id then
    callback(nil, "No active session. Call create_session first.")
    return
  end

  local cfg = config.get()

  local prompt = string.format(
    "%s\n\nPR: %s/%s#%d - %s\n\n<diff>\n%s\n</diff>",
    cfg.review_prompt,
    pr_info.owner,
    pr_info.repo,
    pr_info.number,
    pr_info.title,
    diff_text
  )

  local body = {
    parts = { { type = "text", text = prompt } },
    format = schema.review_schema(),
  }
  if cfg.model then
    body.model = cfg.model
  end

  local endpoint = string.format("/session/%s/message", state.session_id)
  post_async(endpoint, body, function(resp, err)
    if err then
      callback(nil, err)
      return
    end

    -- Try multiple paths to extract the structured output.
    -- OpenCode may return it in different shapes depending on the version.
    local structured = nil

    -- Helper: if the value is a JSON string, decode it into a table
    local function ensure_table(val)
      if type(val) == "string" then
        local ok, decoded = pcall(vim.json.decode, val)
        if ok and type(decoded) == "table" then
          return decoded
        end
      end
      return val
    end

    -- Path 1: resp.info.structured (actual OpenCode server response shape)
    if not structured and resp.info and resp.info.structured then
      structured = ensure_table(resp.info.structured)
    end

    -- Path 2: resp.info.structured_output (SDK-style)
    if not structured and resp.info and resp.info.structured_output then
      structured = resp.info.structured_output
    end

    -- Path 3: resp.structured_output (direct)
    if not structured and resp.structured_output then
      structured = resp.structured_output
    end

    -- Path 4: resp.data.info.structured (wrapped response)
    if not structured and resp.data and resp.data.info then
      structured = resp.data.info.structured or resp.data.info.structured_output
    end

    -- Path 4: Search through parts for a tool-result or tool-use part
    -- containing the StructuredOutput tool's JSON payload
    if not structured then
      local parts = resp.parts or (resp.data and resp.data.parts) or {}
      for _, part in ipairs(parts) do
        -- Check tool-use parts (the AI calls StructuredOutput with the JSON)
        if part.type == "tool-use" or part.type == "tool_use" then
          local input = part.input or part.args or part.arguments
          if input then
            -- Input might be a string (JSON) or already a table
            if type(input) == "string" then
              local ok, decoded = pcall(vim.json.decode, input)
              if ok and decoded.findings then
                structured = decoded
                break
              end
            elseif type(input) == "table" and input.findings then
              structured = input
              break
            end
          end
        end

        -- Check tool-result parts
        if part.type == "tool-result" or part.type == "tool_result" then
          local content = part.content or part.output or part.text
          if content then
            if type(content) == "string" then
              local ok, decoded = pcall(vim.json.decode, content)
              if ok and decoded.findings then
                structured = decoded
                break
              end
            elseif type(content) == "table" and content.findings then
              structured = content
              break
            end
          end
        end

        -- Check text parts for JSON (the model may emit it as plain text)
        if part.type == "text" and part.text then
          -- Try extracting JSON from markdown code fences
          local json_str = part.text:match("```json%s*(.-)%s*```")
          if json_str then
            local ok, decoded = pcall(vim.json.decode, json_str)
            if ok and decoded.findings then
              structured = decoded
              break
            end
          end
          -- Try the whole text as JSON
          local ok, decoded = pcall(vim.json.decode, part.text)
          if ok and type(decoded) == "table" and decoded.findings then
            structured = decoded
            break
          end
        end
      end
    end

    -- Path 5: Try parsing the entire response body as the structured output
    -- (some configurations return the structured data as the top-level object)
    if not structured and resp.findings then
      structured = resp
    end

    if structured and structured.findings then
      callback(structured, nil)
    else
      -- Log the response shape for debugging
      local keys = vim.tbl_keys(resp)
      local debug_info = "Response keys: " .. table.concat(keys, ", ")
      if resp.info then
        debug_info = debug_info .. " | info keys: " .. table.concat(vim.tbl_keys(resp.info), ", ")
      end
      if resp.parts then
        local part_types = {}
        for _, p in ipairs(resp.parts) do
          table.insert(part_types, p.type or "unknown")
        end
        debug_info = debug_info .. " | part types: " .. table.concat(part_types, ", ")
      end
      vim.notify("[docent] " .. debug_info, vim.log.levels.WARN)
      callback(nil, "Could not extract structured review from AI response")
    end
  end, 180000) -- 3 minute timeout for large reviews
end

---Ask a follow-up question about a specific finding.
---@param finding_context string The finding title and explanation for context
---@param question string The user's question
---@param callback fun(answer: string|nil, err: string|nil)
function M.ask_followup(finding_context, question, callback)
  if not state.session_id then
    callback(nil, "No active session")
    return
  end

  local prompt = string.format(
    "Regarding the finding: %s\n\nUser question: %s\n\nProvide a clear, specific answer. Include code examples if relevant.",
    finding_context,
    question
  )

  local body = {
    parts = { { type = "text", text = prompt } },
  }
  local cfg = config.get()
  if cfg.model then
    body.model = cfg.model
  end

  local endpoint = string.format("/session/%s/message", state.session_id)
  post_async(endpoint, body, function(resp, err)
    if err then
      callback(nil, err)
      return
    end
    -- Extract text from response parts
    local parts = resp.parts or {}
    local texts = {}
    for _, part in ipairs(parts) do
      if part.type == "text" and part.text then
        table.insert(texts, part.text)
      end
    end
    if #texts > 0 then
      callback(table.concat(texts, "\n"), nil)
    else
      callback(nil, "Empty response from AI")
    end
  end)
end

---Get the current session ID.
---@return string|nil
function M.get_session_id()
  return state.session_id
end

---Get the server URL.
---@return string|nil
function M.get_server_url()
  return state.server_url
end

---Clean up: stop auto-started server.
function M.shutdown()
  if state.server_job then
    vim.fn.jobstop(state.server_job)
    state.server_job = nil
  end
  state.session_id = nil
end

return M
