local M = {}
local Job = require("plenary.job")
local fidget = require("fidget")

local active = nil

-- Retrieves the API key from the environment variable specified by `name`.
-- @param name The name of the environment variable containing the API key.
-- @return The API key value or nil if not found.
local function get_api_key(name)
    return name and os.getenv(name)
end

-- Gets all lines in the current buffer up to the cursor's position.
-- @return A string containing all lines concatenated with newlines.
function M.get_lines_until_cursor()
    local current_buffer = vim.api.nvim_get_current_buf()
    local current_window = vim.api.nvim_get_current_win()
    local cursor_position = vim.api.nvim_win_get_cursor(current_window)
    local row = cursor_position[1]

    local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)

    return table.concat(lines, "\n")
end

-- Gets all lines in the current buffer after the cursor's position.
-- @return A string containing all lines after the cursor concatenated with newlines.
function M.get_lines_after_cursor()
    local current_buffer = vim.api.nvim_get_current_buf()
    local current_window = vim.api.nvim_get_current_win()
    local cursor_position = vim.api.nvim_win_get_cursor(current_window)
    local row = cursor_position[1]

    local total_lines = vim.api.nvim_buf_line_count(current_buffer)

    local lines = vim.api.nvim_buf_get_lines(current_buffer, row - 1, total_lines, true)

    return table.concat(lines, "\n")
end

-- Retrieves the visually selected text in the current buffer, handling different visual modes.
-- @return A table of lines for line-wise selection, a table of text for character-wise selection, or all buffer lines for block selection.
function M.get_visual_selection()
    local _, srow, scol = unpack(vim.fn.getpos("v"))
    local _, erow, ecol = unpack(vim.fn.getpos("."))

    if vim.fn.mode() == "V" then
        if srow > erow then
            return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
        else
            return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
        end
    end

    if vim.fn.mode() == "v" then
        if srow < erow or (srow == erow and scol <= ecol) then
            return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
        else
            return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
        end
    end

    if vim.fn.mode() == "\22" then
        return vim.api.nvim_buf_get_lines(0, 0, -1, {})
    end
end

-- Constructs cURL arguments for making a request to an Anthropic API endpoint.
-- @param opts Configuration options including provider details and request body.
-- @param prompt The user prompt to send in the request.
-- @param system_prompt The system prompt to include in the request.
-- @return A table of cURL arguments.
function M.get_anthropic_curl_args(opts, prompt, system_prompt)
    local url = opts.provider.url
    local api_key = get_api_key(opts.provider.api_key_name)
    local data = {
        system = system_prompt,
        messages = { { role = "user", content = prompt } },
        model = opts.provider.model,
        stream = true,
        max_tokens = 4096,
    }

    if opts.body then
        for k, v in pairs(opts.body) do
            data[k] = v
        end
    end

    local args = { "--fail-with-body", "-N", "-X", "POST", "-H", "Content-Type: application/json", "-d", vim.json.encode(data) }
    if api_key then
        table.insert(args, "-H")
        table.insert(args, "x-api-key: " .. api_key)
        table.insert(args, "-H")
        table.insert(args, "anthropic-version: 2023-06-01")
    end
    table.insert(args, url)
    return args
end

-- Constructs cURL arguments for making a request to an OpenAI API endpoint.
-- @param opts Configuration options including provider details and request body.
-- @param prompt The user prompt to send in the request.
-- @param system_prompt The system prompt to include in the request.
-- @return A table of cURL arguments.
function M.get_openai_curl_args(opts, prompt, system_prompt)
    local url = opts.provider.url
    local api_key = get_api_key(opts.provider.api_key_name)
    local data = {
        messages = { { role = "system", content = system_prompt }, { role = "user", content = prompt } },
        model = opts.provider.model,
        stream = true,
    }

    if opts.body then
        for k, v in pairs(opts.body) do
            data[k] = v
        end
    end

    local args = { "--fail-with-body", "-N", "-X", "POST", "-H", "Content-Type: application/json", "-d", vim.json.encode(data) }
    if api_key then
        table.insert(args, "-H")
        table.insert(args, "Authorization: Bearer " .. api_key)
    end
    table.insert(args, url)
    return args
end

-- Inserts a string at the current cursor position in the buffer, updating the cursor position accordingly.
-- @param str The string to insert.
function M.insert_string_at_cursor(str)
    vim.schedule(function()
        local current_window = vim.api.nvim_get_current_win()
        local cursor_position = vim.api.nvim_win_get_cursor(current_window)
        local row, col = cursor_position[1], cursor_position[2]

        local lines = vim.split(str, "\n")

        vim.cmd("undojoin")
        vim.api.nvim_put(lines, "c", true, true)

        local num_lines = #lines
        local last_line_length = #lines[num_lines]
        vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
    end)
end

-- Constructs a prompt based on the current buffer content and options, handling visual selection or lines before/after the cursor.
-- @param opts Configuration options including whether to replace selection or include text after the cursor.
-- @return The constructed prompt string.
local function get_prompt(opts)
    local replace = opts.replace
    local include_after = opts.include_after
    local visual_lines = M.get_visual_selection()
    local prompt = ""

    if visual_lines then
        prompt = table.concat(visual_lines, "\n")
        if replace then
            vim.api.nvim_command("normal! c")
        else
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("Esc", false, true, true), "nx", false)
        end
    else
        prompt = M.get_lines_until_cursor()
    end

    if include_after then
        prompt = prompt .. "\n\nAFTER CURSOR:\n" .. M.get_lines_after_cursor()
    end

    return prompt
end

-- Handles streaming data from Anthropic API responses, inserting text content at the cursor.
-- @param data The raw data received from the API stream.
-- @param event The event type from the streaming response.
function M.handle_anthropic_spec_data(data, event)
    if event == "content_block_delta" then
        local json = vim.json.decode(data)
        if json.delta and json.delta.text then
            M.insert_string_at_cursor(json.delta.text)
        end
    end
end

-- Handles streaming data from OpenAI API responses, inserting text content at the cursor.
-- @param data The raw data received from the API stream.
-- @param event The event type from the streaming response (not used in this implementation).
function M.handle_openai_spec_data(data, event)
    if data:match('"delta":') then
        local json = vim.json.decode(data)
        if json.choices and json.choices[1] and json.choices[1].delta then
            local delta = json.choices[1].delta
            if delta.content then
                M.insert_string_at_cursor(delta.content)
            end
        end
    end
end

-- Initiates a streaming API request and processes the response, inserting text at the cursor.
-- @param opts Configuration options including provider, prompts, and data handling functions.
-- @return The active job object managing the streaming process.
local function stream_at_cursor(opts)
    if active then
        active.job:shutdown()
        active = nil
    end
    active = {}

    active.progress_handle = fidget.progress.handle.create({
        title = "DANAI",
        message = "Pending",
        lsp_client = { name = opts.provider.model },
    })

    active.job = Job:new({
        command = "curl",
        args = opts.get_curl_args(opts, get_prompt(opts), opts.system_prompt),
        on_stdout = function(_, line)
            local event = line:match("^event: (.+)$")
            if event then
                active.event = event
                return
            end
            local data_match = line:match("^data: (.+)$")
            if data_match then
                active.progress_handle:report({ message = "Streaming" })
                opts.handle_data_fn(data_match, active.event)
            end
        end,
        on_exit = function(j, exit_code)
            -- only works with --fail-with-body flag on curl
            if exit_code ~= nil and exit_code ~= 0 then
                vim.schedule(function()
                    active.progress_handle:report({ message = "Failed" })
                    active.progress_handle:cancel()
                    fidget.notify(vim.fn.json_encode(j:result()), vim.log.levels.ERROR)
                end)
            else
                active.progress_handle:finish()
            end
        end,
    })

    vim.keymap.set("n", opts.keymap.cancel, function()
        if active then
            active.progress_handle:report({ message = "Cancelled" })
            active.job:shutdown()
            active.progress_handle:cancel()
            active = nil
        end
    end, { noremap = true, silent = true })

    active.job:start()

    return active
end

M.defaults = {
    provider = {
        url = "",
        model = "",
        api_key_name = "",
        style = "",
        -- body = {},
    },
    suggest_system_prompt = [[
        You should complete the code that you are sent. Do not respond with any of the code that was provided,
        only respond with the new code. Do not talk at all. Only output valid code. 
        Your input will be a section of code which is before the cursor and then the text AFTER CURSOR and then the text after the cursor. 
        Your completion will be inserted betweent these two sections of code.
        Do not provide any backticks that surround the code in your response.
        Never ever output backticks like this ```. Do not output backticks.
        Do not provide too much code that the user may not need.
    ]],
    change_system_prompt = [[
        You should replace the code that you are sent, only following the comments. Do not talk at all. 
        Only output valid code. Do not provide any backticks that surround the code in your response.
        Never ever output backticks like this ```. Any comment that is asking you for something should be 
        removed after you satisfy them and do it while not using backticks. Other comments should left alone.
        Do not not start with ```.
    ]],
    keymap = {
        suggest = "<c-s>",
        change = "<leader>c",
        cancel = "<Esc>",
    },
}

function M.setup(options)
    local opts = vim.tbl_deep_extend("force", {}, M.defaults, options or {})

    local get_curl_args = nil
    local handle_data_fn = nil
    if opts.provider.style == "anthropic" then
        get_curl_args = M.get_anthropic_curl_args
        handle_data_fn = M.handle_anthropic_spec_data
    elseif opts.provider.style == "openai" then
        get_curl_args = M.get_openai_curl_args
        handle_data_fn = M.handle_openai_spec_data
    else
        print("DANAI Unsupported provider style: " .. opts.provider.style)
        return
    end

    local function change()
        stream_at_cursor({
            provider = opts.provider,
            system_prompt = opts.change_system_prompt,
            keymap = opts.keymap,
            get_curl_args = get_curl_args,
            handle_data_fn = handle_data_fn,
            replace = true,
        })
    end

    local function suggest()
        stream_at_cursor({
            provider = opts.provider,
            system_prompt = opts.suggest_system_prompt,
            keymap = opts.keymap,
            get_curl_args = get_curl_args,
            handle_data_fn = handle_data_fn,
            include_after = true,
        })
    end

    vim.keymap.set({ "n", "v", "i" }, opts.keymap.suggest, suggest, { desc = "DANAI suggest" })
    vim.keymap.set({ "n", "v" }, opts.keymap.change, change, { desc = "DANAI change" })
end

return M
