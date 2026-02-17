---
layout: default
title: Getting Started (Legacy Path)
nav_exclude: true
description: "Getting started with RubyLLM MCP - installation, setup, and basic usage"
---

# Getting Started
{: .no_toc }

This guide covers the fundamentals of getting started with RubyLLM MCP, including installation, basic setup, and your first MCP client connection. This will expect you to have a basic knowleage of RubyLLM. If you want to fill in the gaps, you can read the RubyLLM [Getting Started](https://rubyllm.com/guides/getting-started) guide.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Installation

### Prerequisites

- Ruby 3.1.3 or higher
- RubyLLM gem installed
- An LLM provider API key (OpenAI, Anthropic, or Google)

### Installing the Gem

Add RubyLLM MCP to your project:

```bash
bundle add ruby_llm-mcp
```

Or add to your Gemfile:

```ruby
gem 'ruby_llm-mcp'
```

Then install:

```bash
bundle install
```

## Basic Setup

### Configure RubyLLM

First, configure RubyLLM with your preferred provider:

```ruby
require 'ruby_llm/mcp'

# For OpenAI
RubyLLM.configure do |config|
  config.openai_api_key = "your-openai-key"
end
```

### Your First MCP Client

Create a connection to an MCP server:

```ruby
# Connect to a local MCP server via stdio
client = RubyLLM::MCP.client(
  name: "my-first-server",
  transport_type: :stdio,
  config: {
    command: "npx",
    args: ["@modelcontextprotocol/server-filesystem", "/path/to/directory"]
  }
)

# Check if the connection is alive
puts client.alive? # => true
```

## Basic Usage

### Using MCP Tools

MCP tools are automatically converted into RubyLLM-compatible tools:

```ruby
# Get all available tools
tools = client.tools
puts "Available tools:"
tools.each do |tool|
  puts "- #{tool.name}: #{tool.description}"
end

# Use tools in a chat
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*client.tools)

response = chat.ask("List the files in the current directory")
puts response
```

### Manual Tool Execution

You can also execute tools directly:

```ruby
# Execute a specific tool
tool = client.tool("read_file")
result = tool.execute(path: "README.md")

puts result
```

### Working with Resources

Resources provide static or dynamic data for conversations:

```ruby
# Get available resources
resources = client.resources
puts "Available resources:"
resources.each do |resource|
  puts "- #{resource.name}: #{resource.description}"
end

# Use a resource in a chat
chat = RubyLLM.chat(model: "gpt-4")
chat.with_resource(client.resource("project_structure"))

response = chat.ask("What is the structure of this project?")
puts response
```

## Connection Management

### Manual Connection Control

You can control the connection lifecycle manually:

```ruby
# Create a client without starting it
client = RubyLLM::MCP.client(
  name: "my-server",
  transport_type: :stdio,
  start: false,
  config: { command: "node", args: ["server.js"] }
)

# Start the connection
client.start

# Check if it's alive
puts client.alive? # => true

# Restart if needed
client.restart!

# Stop the connection
client.stop
```

### Health Checks

Monitor your MCP server connection via ping:

```ruby
# Ping the server to see if you can successful communicate with it the MCP server
if client.ping
  puts "Server is responsive"
else
  puts "Server is not responding"
end

# Check connection is still marked as alive
puts "Connection alive: #{client.alive?}"
```

## Error Handling

Handle common errors when working with MCP:

```ruby
begin
  client = RubyLLM::MCP.client(
    name: "my-server",
    transport_type: :stdio,
    config: {
      command: "nonexistent-command"
    }
  )
rescue RubyLLM::MCP::Errors::TransportError => e
  puts "Failed to connect: #{e.message}"
end

# Handle tool execution errors
begin
  result = client.execute_tool(
    name: "nonexistent_tool",
    parameters: {}
  )
rescue RubyLLM::MCP::Errors::ToolError => e
  puts "Tool error: #{e.message}"
end
```

## Next Steps

Now that you have the basics down, explore these topics:

- **[Configuration]({% link configuration.md %})** - Advanced client configuration
- **[Tools]({% link server/tools.md %})** - Deep dive into MCP tools
- **[Resources]({% link server/resources.md %})** - Working with resources and templates
- **[Prompts]({% link server/prompts.md %})** - Using predefined prompts

## Common Patterns

### Multiple Clients

Manage multiple MCP servers simultaneously:

```ruby
# Create multiple clients
file_client = RubyLLM::MCP.client(
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "npx",
    args: ["@modelcontextprotocol/server-filesystem", "/"]
  }
)

api_client = RubyLLM::MCP.client(
  name: "api-server",
  transport_type: :sse,
  config: {
    url: "https://api.example.com/mcp/sse"
  }
)

# Use tools from both clients
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*file_client.tools, *api_client.tools)

response = chat.ask("Read the config file and make an API call")
puts response
```

### Combining Features

Use tools, resources, and prompts together:

```ruby
chat = RubyLLM.chat(model: "gpt-4")

# Add tools for capabilities
chat.with_tools(*client.tools)

# Add resources for context
chat.with_resource(client.resource("project_overview"))

# Add prompts for guidance
chat.with_prompt(
  client.prompt("analysis_template"),
  arguments: { focus: "performance" }
)

response = chat.ask("Analyze the project")
puts response
```
