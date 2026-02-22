---
layout: default
title: Home
nav_exclude: true
description: "RubyLLM::MCP brings MCP tools, resources, and prompts into RubyLLM with a clean Ruby API."
permalink: /
---

<h1>
  <div class="logo-container">
    <img src="/assets/images/rubyllm-mcp-logo-text.svg" alt="RubyLLM::MCP" height="120" width="250">
    <iframe src="https://ghbtns.com/github-btn.html?user=patvice&repo=ruby_llm-mcp&type=star&count=true&size=large" frameborder="0" scrolling="0" width="170" height="30" title="GitHub" style="vertical-align: middle; display: inline-block;"></iframe>
  </div>
</h1>

RubyLLM::MCP gives you a direct way to use [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) servers from [RubyLLM](https://github.com/crmne/ruby_llm).
{: .fs-6 .fw-300 }

**Highlights:** **Tools**, **Resources**, **Prompts**, **MCP OAuth 2.1 auth support**, **Notification + response handlers**, **Rails OAuth setup**, **Browser OAuth for CLI**.

<a href="{% link getting-started/getting-started.md %}" class="btn btn-primary fs-5 mb-4 mb-md-0 mr-2" style="margin: 0;">Get started</a>
<a href="https://github.com/patvice/ruby_llm-mcp" class="btn fs-5 mb-4 mb-md-0 mr-2" style="margin: 0;">GitHub</a>

<div class="badge-container">
  <a href="https://badge.fury.io/rb/ruby_llm-mcp"><img src="https://badge.fury.io/rb/ruby_llm-mcp.svg" alt="Gem Version" /></a>
  <a href="https://rubygems.org/gems/ruby_llm-mcp"><img alt="Gem Downloads" src="https://img.shields.io/gem/dt/ruby_llm-mcp"></a>
</div>

---

## Why RubyLLM::MCP?

MCP integration in Ruby apps should be easy to reason about.

RubyLLM::MCP focuses on:

- Ruby-first APIs for using MCP tools, resources, and prompts in RubyLLM chat workflows
- Stable protocol defaults (`2025-06-18`) with explicit draft opt-in (`2026-01-26`)
- Built-in notification and response handlers for real-time and interactive workflows
- MCP OAuth 2.1 authentication support (PKCE, dynamic registration, discovery, and automatic token refresh)
- OAuth setup paths for Rails apps (per-user connections) and browser-based CLI flows
- Straightforward integration for Ruby apps, background jobs, and Rails projects

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
puts chat.ask("Find test files with pending TODOs")
```

```ruby
# Resources (simple)
resource = client.resource("release_notes")
chat = RubyLLM.chat(model: "gpt-4.1-mini")
chat.with_resource(resource)

# More complex: use client.resource_template(...) with chat.with_resource_template(...)
puts chat.ask("Summarize release notes for the team in 5 bullet points.")
```

```ruby
# Prompts (simple)
prompt = client.prompt("code_review")
chat = RubyLLM.chat(model: "gpt-4.1-mini")

response = chat.ask_prompt(
  prompt,
  arguments: {
    language: "ruby",
    focus: "security"
  }
)

# More complex: combine prompts + resources/templates in the same chat workflow
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

```bash
bundle add ruby_llm-mcp
```

or in `Gemfile`:

```ruby
gem "ruby_llm-mcp"
```

Optional official SDK adapter:

```ruby
gem "mcp", "~> 0.7"
```

## Rails

```bash
rails generate ruby_llm:mcp:install
```

For per-user OAuth flows:

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

Use connection blocks in jobs/services/controllers for clean startup and cleanup.

See **[Rails Integration]({% link guides/rails-integration.md %})** for end-to-end patterns.

## Documentation

- **[Getting Started]({% link getting-started/getting-started.md %})**
- **[Configuration]({% link configuration.md %})**
- **[Adapters]({% link guides/adapters.md %})**
- **[Server: Tools, Resources, Prompts]({% link server/index.md %})**
- **[Client Features]({% link client/index.md %})**
- **[Extensions and MCP Apps]({% link extensions/index.md %})**
- **[Guides]({% link guides/index.md %})**

## Contributing

Contributions are welcome on [GitHub](https://github.com/patvice/ruby_llm-mcp).

## License

Released under the MIT License.
