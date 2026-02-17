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

## Minimal Flow

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

## Next Steps

- **[Getting Started]({% link getting-started/getting-started.md %})** - Build your first integration
- **[Configuration]({% link configuration.md %})** - Configure adapters, transports, and behavior
- **[Server]({% link server/index.md %})** - Use tools/resources/prompts
- **[Client]({% link client/index.md %})** - Enable client-side capabilities
