---
layout: default
title: Home
nav_order: 1
description: "MCP made simple for RubyLLM."
permalink: /
---

<div class="logo-container">
  <img src="/assets/images/rubyllm-mcp-logo-text.svg" alt="RubyLLM" height="120" width="250">
  <iframe src="https://ghbtns.com/github-btn.html?user=patvice&repo=ruby_llm-mcp&type=star&count=true&size=large" frameborder="0" scrolling="0" width="170" height="30" title="GitHub" style="vertical-align: middle; display: inline-block;"></iframe>
</div>

**MCP made simple for RubyLLM.**

`ruby_llm-mcp` connects Ruby applications to [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) servers and integrates them directly with [RubyLLM](https://github.com/crmne/ruby_llm).

<div class="badge-container">
  <a href="https://badge.fury.io/rb/ruby_llm-mcp"><img src="https://badge.fury.io/rb/ruby_llm-mcp.svg" alt="Gem Version" /></a>
  <a href="https://rubygems.org/gems/ruby_llm-mcp"><img alt="Gem Downloads" src="https://img.shields.io/gem/dt/ruby_llm-mcp"></a>
</div>

[Getting Started]({% link guides/getting-started.md %}){: .btn } [GitHub](https://github.com/patvice/ruby_llm-mcp){: .btn .btn-green }

## Simple Configuration

```ruby
require 'ruby_llm/mcp'

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
end

RubyLLM::MCP.configure do |config|
  config.request_timeout = 8_000
end

client = RubyLLM::MCP.client(
  name: 'filesystem',
  transport_type: :stdio,
  config: {
    command: 'npx',
    args: ['@modelcontextprotocol/server-filesystem', Dir.pwd]
  }
)
```

## Core Use Cases

```ruby
# Use MCP tools in a chat
chat = RubyLLM.chat(model: 'gpt-4o-mini')
chat.with_tools(*client.tools)

puts chat.ask('List the Ruby files in this project and summarize what you find.')
```

```ruby
# Add a server resource to chat context
resource = client.resource('project_readme')

chat = RubyLLM.chat(model: 'gpt-4o-mini')
chat.with_resource(resource)

puts chat.ask('Summarize this project in 5 bullets.')
```

```ruby
# Execute a predefined MCP prompt with arguments
prompt = client.prompt('code_review')
chat = RubyLLM.chat(model: 'gpt-4o-mini')

response = chat.ask_prompt(prompt, arguments: {
  language: 'ruby',
  focus: 'security'
})

puts response
```

```ruby
# Authenticate to a protected MCP server with browser OAuth
client = RubyLLM::MCP.client(
  name: 'oauth-server',
  transport_type: :streamable,
  start: false,
  config: {
    url: 'https://mcp.example.com/mcp',
    oauth: { scope: 'mcp:read mcp:write' }
  }
)

client.oauth(type: :browser).authenticate
client.start
```

```ruby
# Poll a long-running MCP task and fetch its final result
task = client.task_get('task-123')

until task.completed? || task.failed? || task.cancelled?
  sleep((task.poll_interval || 250) / 1000.0)
  task = task.refresh
end

if task.completed?
  payload = client.task_result(task.task_id)
  puts payload.dig('content', 0, 'text')
else
  puts "Task ended with status: #{task.status}"
end
```

## Support At A Glance

- **Native MCP client implementation (`:ruby_llm`)** with full protocol support through `2025-11-25`
- **Official MCP SDK adapter support (`:mcp_sdk`)** via the `mcp` gem for teams that prefer SDK-backed integration
- **OAuth implementation** for authenticated streamable HTTP MCP servers
- **Transports:** `stdio`, `sse`, `streamable` / `streamable_http`
- **Core server features:** tools, resources, resource templates, prompts, notifications
- **Advanced client features:** sampling, roots, progress tracking, human-in-the-loop, elicitation
- **Task lifecycle APIs** (`tasks/list`, `tasks/get`, `tasks/result`, `tasks/cancel`) are experimental

{: .warning }
MCP task support is experimental and subject to change in both the MCP spec and this gem's implementation.

## Install

Add to your Gemfile:

```ruby
gem 'ruby_llm-mcp'
```

Optional (for `:mcp_sdk` adapter):

```ruby
gem 'mcp', '~> 0.7'
```

Then run:

```bash
bundle install
```

## Setup

1. Set your RubyLLM provider credentials (for example `OPENAI_API_KEY`).
2. Start or access an MCP server.
3. Create a `RubyLLM::MCP.client` and attach its tools/resources/prompts to chat flows.

## Documentation

1. **[Getting Started]({% link guides/getting-started.md %})** - Get up and running quickly
2. **[Configuration]({% link configuration.md %})** - Configure clients and transports
3. **[Adapters & Transports]({% link guides/adapters.md %})** - Choose adapters and configure transports
4. **[Server: Tools]({% link server/tools.md %})** - Execute server-side operations
5. **[Server: Resources]({% link server/resources.md %})** - Include data in conversations
6. **[Server: Prompts]({% link server/prompts.md %})** - Use predefined prompts with arguments
7. **[Server: Tasks]({% link server/tasks.md %})** - Poll and manage long-running background work (experimental)
8. **[Server: Notifications]({% link server/notifications.md %})** - Handle real-time updates
9. **[Client: Sampling]({% link client/sampling.md %})** - Allow servers to use your LLM
10. **[Client: Roots]({% link client/roots.md %})** - Provide filesystem access to servers
11. **[Client: Elicitation]({% link client/elicitation.md %})** - Handle user input during conversations

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/patvice/ruby_llm-mcp).

## License

Released under the MIT License.
