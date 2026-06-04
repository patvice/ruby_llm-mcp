---
layout: default
title: Governed MCP Workflows
parent: Advanced
nav_order: 2
description: "Route RubyLLM MCP workflows through a governed OpenAI-compatible endpoint"
---

# Governed MCP Workflows
{: .no_toc }

RubyLLM::MCP brings MCP tools, resources, and prompts into RubyLLM. For production Rails apps, you may also want a central control plane for model access, tool governance, audit trails, and cost controls.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Pattern

Use RubyLLM::MCP for MCP client and tool/resource integration, and route the RubyLLM model call through an OpenAI-compatible governed endpoint.

RubyLLM::MCP remains responsible for:

- connecting to MCP servers
- converting MCP tools into RubyLLM tools
- loading MCP resources and prompts
- handling OAuth and per-user MCP connections

The governed endpoint can be responsible for:

- model access by tenant, role, or environment
- policy checks before model calls
- audit trails and request traces
- budget limits, quotas, routing, and fallback controls
- centralized reporting across multiple Rails apps

## Example: Tuning Engines

Tuning Engines exposes an OpenAI-compatible endpoint, so it can be configured with RubyLLM's OpenAI provider settings:

```ruby
RubyLLM.configure do |config|
  config.openai_api_key = ENV["TUNING_ENGINES_API_KEY"]
  config.openai_api_base = "https://api.tuningengines.com/v1"
end
```

Then use RubyLLM::MCP normally:

```ruby
require "ruby_llm/mcp"

client = RubyLLM::MCP.client(
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "bunx",
    args: ["@modelcontextprotocol/server-filesystem", Dir.pwd]
  }
)

chat = RubyLLM.chat(
  model: ENV.fetch("TUNING_ENGINES_MODEL", "your-model-alias"),
  provider: :openai,
  assume_model_exists: true
)

chat.with_tools(*client.tools)
puts chat.ask("Find Ruby files modified today and summarize what changed.")
```

Use an inference key for the gateway API key. Keep provider secrets and MCP server secrets in the systems that own them.

## Rails request context

When using this pattern in Rails, pass request context through your application instrumentation so gateway traces and local Rails logs can be correlated:

```ruby
RubyLLM::Instrumentation.with(
  request_id: request.uuid,
  user_id: current_user.id,
  feature: "mcp_code_review"
) do
  chat.with_tools(*current_user.mcp_client.tools)
  chat.ask("Review this change for security concerns.")
end
```

This keeps RubyLLM::MCP focused on MCP integration while the gateway handles organization-level compliance, control, and cost reporting.
