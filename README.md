<div align="center">

<img src="docs/assets/images/rubyllm-mcp-logo-text.svg#gh-light-mode-only" alt="RubyLLM::MCP" height="120" width="250">
<img src="docs/assets/images/rubyllm-mcp-logo-text-white.svg#gh-dark-mode-only" alt="RubyLLM::MCP" height="120" width="250">

<strong>MCP for Ruby and RubyLLM, as easy as possible.</strong>

[![Gem Version](https://badge.fury.io/rb/ruby_llm-mcp.svg)](https://badge.fury.io/rb/ruby_llm-mcp)
[![Gem Downloads](https://img.shields.io/gem/dt/ruby_llm-mcp)](https://rubygems.org/gems/ruby_llm-mcp)

</div>

RubyLLM::MCP is a Ruby client for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/), built to work cleanly with [RubyLLM](https://github.com/crmne/ruby_llm). Aiming to be completely spec compliant.

Use MCP tools, resources, and prompts from your RubyLLM chats over `stdio`, streamable HTTP, or SSE.

**Protocol support:** Fully supports MCP spec `2025-06-18` (stable), with draft spec `2026-01-26` available.

## RubyLLM::MCP Out of the Box

Our goal is to be able to plug MCP into Ruby/RubyLLM apps as easily as possible.

RubyLLM::MCP gives you that:

- Ruby-first API for using MCP tools, resources, and prompts directly in RubyLLM chat workflows
- Stable protocol track by default (`2025-06-18`), with opt-in draft track (`2026-01-26`)
- Built-in notification and response handlers for real-time and interactive workflows
- MCP OAuth 2.1 authentication support (PKCE, dynamic registration, discovery, and automatic token refresh)
- OAuth setup paths for Rails apps (per-user connections) and browser-based CLI flows
- Straightforward integration for any Ruby app, background job, or Rails project using RubyLLM

## Show me the code

```ruby
# Basic setup
require "ruby_llm/mcp"

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY")
end

client = RubyLLM::MCP.client(
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "bunx",
    args: ["@modelcontextprotocol/server-filesystem", Dir.pwd]
  }
)

chat = RubyLLM.chat(model: "gpt-4.1-mini")
chat.with_tools(*client.tools)

puts chat.ask("Find Ruby files modified today and summarize what changed.")
```

```ruby
# Resources
resource = client.resource("release_notes")
chat = RubyLLM.chat(model: "gpt-4.1-mini")
chat.with_resource(resource)

puts chat.ask("Summarize release notes for the team in 5 bullet points.")
```

```ruby
# Prompts
prompt = client.prompt("code_review")
chat = RubyLLM.chat(model: "gpt-4.1-mini")

response = chat.ask_prompt(
  prompt,
  arguments: {
    language: "ruby",
    focus: "security"
  }
)

puts response
```

```ruby
# Handlers (response + notifications)
client.on_progress do |progress|
  puts "Progress: #{progress.progress}% - #{progress.message}"
end

client.on_logging do |logging|
  puts "[#{logging.level}] #{logging.message}"
end

chat = RubyLLM.chat(model: "gpt-4.1-mini")
chat.with_tools(*client.tools)

chat.ask("Run a repository scan and summarize risks.") do |chunk|
  print chunk.content
end
```

```ruby
# OAuth setup (Rails and CLI)
# Rails: per-user OAuth client (after running rails generate ruby_llm:mcp:oauth:install User)
client = current_user.mcp_client
chat = RubyLLM.chat(model: "gpt-4.1-mini")
chat.with_tools(*client.tools)
puts chat.ask("What changed in my connected repos this week?")

# CLI: browser-based OAuth flow
cli_client = RubyLLM::MCP.client(
  name: "oauth-server",
  transport_type: :streamable,
  start: false,
  config: {
    url: ENV.fetch("MCP_SERVER_URL"),
    oauth: { scope: "mcp:read mcp:write" }
  }
)

cli_client.oauth(type: :browser).authenticate
cli_client.start
puts RubyLLM.chat(model: "gpt-4.1-mini").with_tools(*cli_client.tools).ask("List my open tasks.")
cli_client.stop
```

## Features

- **Tools:** Convert MCP tools into RubyLLM-compatible tools
- **Resources:** Work with resources and resource templates in chat context
- **Prompts:** Execute server prompts with typed arguments
- **Transports:** `:stdio`, `:streamable`, and `:sse`
- **Client capabilities:** Sampling, roots, progress tracking, and elicitation
- **Handlers:** Built-in notification and response handlers for real-time and interactive workflows
- **MCP Authentication:** OAuth 2.1 support with PKCE, dynamic registration, discovery, and automatic token refresh
- **OAuth setup paths:** Rails per-user OAuth setup and browser-based OAuth for CLI tools
- **Extensions:** Global/per-client extension negotiation, including MCP Apps
- **Multi-client support:** Manage multiple MCP servers in one workflow
- **Protocol control:** Stable default with explicit draft opt-in
- **Adapters:** Native `:ruby_llm` adapter (full feature set) and optional `:mcp_sdk`

## Installation

Add to your Gemfile:

```ruby
gem "ruby_llm-mcp"
```

Then run:

```bash
bundle install
```

If you want the official SDK adapter, also add:

```ruby
gem "mcp", "~> 0.7"
```

## Rails

```bash
rails generate ruby_llm:mcp:install
```

For OAuth-based user connections:

```bash
rails generate ruby_llm:mcp:oauth:install User
```

OAuth quick example:

```ruby
client = RubyLLM::MCP.client(
  name: "oauth-server",
  transport_type: :streamable,
  start: false,
  config: {
    url: ENV.fetch("MCP_SERVER_URL"),
    oauth: { scope: "mcp:read mcp:write" }
  }
)

client.oauth(type: :browser).authenticate
client.start

chat = RubyLLM.chat(model: "gpt-4.1-mini")
chat.with_tools(*client.tools)
puts chat.ask("What should I prioritize today?")

client.stop
```

Then use explicit connection blocks in jobs/controllers/services:

```ruby
RubyLLM::MCP.establish_connection do |clients|
  chat = RubyLLM.chat(model: "gpt-4.1-mini")
  chat.with_tools(*clients.tools)
  chat.ask("Analyze this pull request and list risks.")
end
```

## Documentation

- [rubyllm-mcp.com](https://rubyllm-mcp.com/)
- [Getting Started](https://rubyllm-mcp.com/getting-started/getting-started.html)
- [Rails Integration](https://rubyllm-mcp.com/guides/rails-integration.html)
- [Adapters and transports](https://rubyllm-mcp.com/guides/adapters.html)

## Contributing

Issues and pull requests are welcome at [patvice/ruby_llm-mcp](https://github.com/patvice/ruby_llm-mcp).

## License

Released under the MIT License.
