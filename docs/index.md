---
layout: default
title: Home
nav_order: 1
description: "RubyLLM::MCP is a full-featured Ruby Client for the Model Context Protocol (MCP)."
permalink: /
---

<div class="logo-container">
  <img src="/assets/images/rubyllm-mcp-logo-text.svg" alt="RubyLLM" height="120" width="250">
  <iframe src="https://ghbtns.com/github-btn.html?user=patvice&repo=ruby_llm-mcp&type=star&count=true&size=large" frameborder="0" scrolling="0" width="170" height="30" title="GitHub" style="vertical-align: middle; display: inline-block;"></iframe>
</div>


A Ruby client for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) that seamlessly integrates with [RubyLLM](https://github.com/crmne/ruby_llm). This gem enables Ruby applications to connect to MCP servers and use their tools, resources, and prompts as part of LLM conversations.

Currently full support for MCP protocol version up to `2025-06-18`.

<div class="badge-container">
  <a href="https://badge.fury.io/rb/ruby_llm-mcp"><img src="https://badge.fury.io/rb/ruby_llm-mcp.svg" alt="Gem Version" /></a>
  <a href="https://rubygems.org/gems/ruby_llm-mcp"><img alt="Gem Downloads" src="https://img.shields.io/gem/dt/ruby_llm-mcp"></a>
</div>

[Getting Started]({% link guides/getting-started.md %}){: .btn } [GitHub](https://github.com/patvice/ruby_llm-mcp){: .btn .btn-green }


## Key Features

- 🎛️ **Dual SDK Support**: Choose between native full-featured implementation or official MCP SDK {: .label .label-green } 0.8+
- 🔌 **Multiple Transport Types**: Streamable HTTP, STDIO, and SSE transports
- 🛠️ **Tool Integration**: Automatically converts MCP tools into RubyLLM-compatible tools
- 📄 **Resource Management**: Access and include MCP resources (files, data) and resource templates in conversations
- 🎯 **Prompt Integration**: Use predefined MCP prompts with arguments for consistent interactions
- 🎨 **Client Features**: Support for sampling, roots, progress tracking, and human-in-the-loop
- 🔧 **Enhanced Chat Interface**: Extended RubyLLM chat methods for seamless MCP integration
- 🔄 **Multiple Client Management**: Create and manage multiple MCP clients simultaneously
- 📚 **Simple API**: Easy-to-use interface that integrates seamlessly with RubyLLM
- 🚀 **Rails Integration**: Built-in Rails support with generators and configuration

## Installation

```bash
bundle add ruby_llm-mcp
```

Or add to your Gemfile:

```ruby
gem 'ruby_llm-mcp'
```

## Quick Start

```ruby
require 'ruby_llm/mcp'

# Configure RubyLLM
RubyLLM.configure do |config|
  config.openai_api_key = "your-api-key"
end

# Connect to an MCP server
client = RubyLLM::MCP.client(
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "bunx",
    args: [
      "@modelcontextprotocol/server-filesystem",
      File.expand_path("..", __dir__)
    ]
  }
)

# Use MCP tools in a chat
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*client.tools)

response = chat.ask("Can you help me search for files in my project?")
puts response
```

## Transport Types

### STDIO Transport

Best for local MCP servers or command-line tools:

```ruby
client = RubyLLM::MCP.client(
  name: "local-server",
  transport_type: :stdio,
  config: {
    command: "python",
    args: ["-m", "my_mcp_server"],
    env: { "DEBUG" => "1" }
  }
)
```

### Streamable HTTP Transport

Best for HTTP-based MCP servers that support streaming:

```ruby
client = RubyLLM::MCP.client(
  name: "streaming-server",
  transport_type: :streamable,
  config: {
    url: "https://your-mcp-server.com/mcp",
    headers: { "Authorization" => "Bearer your-token" }
  }
)
```

### SSE Transport

Best for web-based MCP servers:

```ruby
client = RubyLLM::MCP.client(
  name: "web-server",
  transport_type: :sse,
  config: {
    url: "https://your-mcp-server.com/mcp/sse",
    headers: { "Authorization" => "Bearer your-token" }
  }
)
```

## Core Concepts

### Tools

MCP tools are automatically converted into RubyLLM-compatible tools, enabling LLMs to execute server-side operations.

### Resources

Static or dynamic data that can be included in conversations - from files to API responses.

### Prompts

Pre-defined prompts with arguments for consistent interactions across your application.

### Notifications

Real-time updates from MCP servers including logging, progress, and resource changes.

## Getting Started

1. **[Getting Started]({% link guides/getting-started.md %})** - Get up and running quickly
2. **[Configuration]({% link configuration.md %})** - Configure clients and transports
3. **[Rails Integration]({% link guides/rails-integration.md %})** - Use with Rails applications
4. **[Transports]({% link guides/transports.md %})** - Build custom transport implementations

## Server Interactions

1. **[Working with Tools]({% link server/tools.md %})** - Execute server-side operations
2. **[Using Resources]({% link server/resources.md %})** - Include data in conversations
3. **[Prompts]({% link server/prompts.md %})** - Use predefined prompts with arguments
4. **[Notifications]({% link server/notifications.md %})** - Handle real-time updates

## Client Interactions

1. **[Sampling]({% link client/sampling.md %})** - Allow servers to use your LLM
2. **[Roots]({% link client/roots.md %})** - Provide filesystem access to servers
3. **[Elicitation]({% link client/elicitation.md %})** - Handle user input during conversations

## Examples

Complete examples are available in the [`examples/`](https://github.com/patvice/ruby_llm-mcp/tree/main/examples) directory:

- **Local MCP Server**: Complete stdio transport example
- **SSE with GPT**: Server-sent events with OpenAI
- **Resource Management**: List and use resources
- **Prompt Integration**: Use prompts with streamable transport

## Contributing

We welcome contributions! Bug reports and pull requests are welcome on [GitHub](https://github.com/patvice/ruby_llm-mcp).

## License

Released under the MIT License.
