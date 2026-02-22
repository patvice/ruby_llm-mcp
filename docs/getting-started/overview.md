---
layout: default
title: Overview
parent: Getting Started
nav_order: 2
description: "A high-level overview of RubyLLM MCP concepts and architecture"
---

# Overview
{: .no_toc }

RubyLLM MCP connects RubyLLM chats to Model Context Protocol (MCP) servers so your app can use external tools, resources, prompts, and notifications in a consistent API.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## What RubyLLM MCP Adds

- Connect to MCP servers over `stdio`, `streamable/http`, and `sse`
- Map MCP tools into RubyLLM-compatible tools
- Read MCP resources and resource templates into chat context
- Retrieve and execute MCP prompts with arguments
- Handle real-time server notifications and progress events

## Simplicity with RubyLLM

RubyLLM MCP is designed so the basic integration path stays short:

```ruby
require "ruby_llm/mcp"

client = RubyLLM::MCP.client(
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "npx",
    args: ["@modelcontextprotocol/server-filesystem", "."]
  }
)

chat = RubyLLM.chat(model: "gpt-4.1")
chat.with_tools(*client.tools)
puts chat.ask("List the top-level files and summarize this project")
```

The same client API can then be extended with resources, prompts, notifications, and tasks.

## High-Level Architecture

1. **RubyLLM Chat** - Your application chat/session logic
2. **RubyLLM MCP Client** - Connection and protocol wrapper
3. **Adapter** - `:ruby_llm` (full) or `:mcp_sdk` (core/passive extensions)
4. **Transport** - `stdio`, `streamable`, `sse`
5. **MCP Server** - External capability provider

## Core Interaction Model

RubyLLM MCP is split into server and client capability surfaces:

- **Server**: tools, resources, prompts, notifications
- **Client**: sampling, roots, elicitation
- **Extensions**: optional capability negotiation (including MCP Apps/UI)

## Response Patterns

RubyLLM MCP commonly uses three response patterns:

1. **Synchronous response**: Immediate return value from a request, such as `tool.execute`.
2. **Notification-driven async updates**: Server-sent updates during execution (logging, progress, resource updates).
3. **Task lifecycle response**: Pollable background work via `tasks/get`, `tasks/result`, and optional cancellation.

Use synchronous responses for short operations, notifications for real-time status updates, and tasks for long-running workflows.

## Native vs MCP SDK Adapter

RubyLLM MCP supports two adapters:

- **Native (`:ruby_llm`)** - Full-featured implementation with advanced MCP capabilities (sampling, roots, notifications, progress, tasks, elicitation).
- **MCP SDK (`:mcp_sdk`)** - Official SDK-backed adapter focused on core surfaces (tools, resources, prompts, templates, logging).

Choose `:ruby_llm` when you need full protocol coverage and advanced interactions. Choose `:mcp_sdk` when you only need core MCP surfaces and want SDK alignment.

For the full feature matrix, see **[Adapters & Transports]({% link guides/adapters.md %})**.

## Minimal Sync Flow

```ruby
require "ruby_llm/mcp"

client = RubyLLM::MCP.client(
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "npx",
    args: ["@modelcontextprotocol/server-filesystem", "."]
  }
)

chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*client.tools)
response = chat.ask("List files in this project")
puts response
```

## Minimal Task Flow

```ruby
task = client.task_get("task-123")

until task.completed? || task.failed? || task.cancelled?
  sleep((task.poll_interval || 250) / 1000.0)
  task = task.refresh
end

puts(task.completed? ? task.result : task.status_message)
```

## Next Steps

- **[Getting Started]({% link getting-started/getting-started.md %})** - Build your first integration
- **[Configuration]({% link configuration.md %})** - Configure adapters, transports, and behavior
- **[Adapters & Transports]({% link guides/adapters.md %})** - Choose native vs MCP SDK
- **[Notifications]({% link server/notifications.md %})** - Handle async server updates
- **[Tasks]({% link server/tasks.md %})** - Manage long-running operations
- **[Server]({% link server/index.md %})** - Use tools/resources/prompts
- **[Client]({% link client/index.md %})** - Enable client-side capabilities
