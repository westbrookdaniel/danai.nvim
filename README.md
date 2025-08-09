# danai.nvim

A Neovim plugin for AI-powered code completion.

- Supports Anthropic and OpenAI compatible API providers.
- Configurable keymappings for suggesting and changing code.
- Progress feedback using `fidget.nvim`.

## Features

This plugin has 2 core features. Both of these features provide different
wasy of streaming an LLMs response to your cursors position.
These can be interrupted by pressing the keymap for cancel (`<Esc>`).

### Suggest (`<C-S>`)

Uses all of the code in the current file to attempt a completion.
You can provide guidance on what it should complete
by providing a comment like `TODO AI Write a fib function`.

### Change (`<leader>c`)

Use visual mode to select the context you want to provide to an LLM for replacement.
This method _requires_ adding a comment for the AI to follow, which I suggest
denoting using something like `TODO AI` in your comment.

## Installation

### Prerequisites

- Neovim 0.7.0 or higher.
- `plenary.nvim` and `fidget.nvim` installed as dependencies.
- `curl` installed on your system for API requests.
- API keys set as environment variables.

### Setup with Lazy.nvim

Add the following to your Lazy.nvim configuration (or any other plugin manager):

```lua
{
    "westbrookdaniel/danai.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "j-hui/fidget.nvim" },
    opts = {
        provider = {
            -- I recommend using non-reasoning models with a lower time to first token.
            -- Some models may require tweaking the system prompts for better reliability.
            -- Here are some of my recommendations that balance cost and performance.

            -- gpt-oss-120b through groq on openrouter
            url = "https://openrouter.ai/api/v1/chat/completions",
            model = "openai/gpt-oss-120b",
            api_key_name = "OPENROUTER_API_KEY",
            body = {
                temperature = 0.7,
                provider = { only = { "groq" } },
            },
            style = "openai",

            -- -- claude sonnet 4
            -- url = "https://api.anthropic.com/v1/messages",
            -- model = "claude-sonnet-4-20250514",
            -- api_key_name = "ANTHROPIC_API_KEY",
            -- style = "anthropic",

            -- -- gemini 2.5 flash
            -- url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            -- model = "gemini-2.5-flash",
            -- api_key_name = "GEMINI_API_KEY",
            -- body = { temperature = 0.7 },
            -- style = "openai",
        },
    },
}
```

### Config

Here is an example setup using all available configuration options, shown with the defaults.

````lua
require("danai").setup({
  provider = {
    url = "https://api.anthropic.com/v1/messages", -- API endpoint
    model = "claude-3-5-sonnet-20241022", -- Model name
    api_key_name = "ANTHROPIC_API_KEY", -- Environment variable for API key
    style = "anthropic", -- "anthropic" or "openai"
    -- body = {}, -- Additional request body parameters
  },
  suggest_system_prompt = [[
    You should complete the code that you are sent. Do not respond with any of the code that was provided,
    only respond with the new code. Do not talk at all. Only output valid code.
    Your input will be a section of code which is before the cursor and then the text AFTER CURSOR and then the text after the cursor.
    Your completion will be inserted between these two sections of code.
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
    suggest = "<C-s>", -- Suggest code completion
    change = "<leader>c", -- Replace selected code
    cancel = "<Esc>", -- Cancel ongoing streaming
  },
})
````

## Credits

This plugin is originally based on [yacineMTB/dingllm.nvim](https://github.com/yacineMTB/dingllm.nvim)
which is based on [melbaldove/llm.nvim](https://github.com/melbaldove/llm.nvim).

Thank you both!
