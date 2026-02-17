---
layout: default
title: "MCP Apps"
parent: Advanced
nav_order: 8
description: "A practical guide to getting started with MCP Apps in RubyLLM MCP using core implementation patterns"
nav_exclude: true
---

# MCP Apps
{: .no_toc }

This guide shows a practical starting point for MCP Apps with RubyLLM MCP, focused on the core implementation ideas you need to wire it correctly.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Core Ideas

1. **Negotiate capabilities at the client layer**  
   Register UI capability with `config.extensions.enable_apps`.
2. **Keep metadata where it belongs**  
   Use extension config for capability fields (`mimeTypes`) and `_meta.ui` for tool/resource UI metadata.
3. **Read metadata through RubyLLM MCP objects**  
   Use `apps_metadata` on tools/resources/templates instead of manual hash parsing.
4. **Separate model actions from UI rendering**  
   Keep tool execution and UI content generation explicit so app behavior is predictable.

## Step 1: Enable MCP Apps Capability

```ruby
RubyLLM::MCP.configure do |config|
  config.extensions.enable_apps(
    "mimeTypes" => ["text/html;profile=mcp-app"]
  )
end
```

This advertises `io.modelcontextprotocol/ui` when the session protocol supports extensions (`2025-06-18+` and draft).

## Step 2: Connect a Client

```ruby
client = RubyLLM::MCP.client(
  name: "mcp-app-server",
  adapter: :ruby_llm,
  transport_type: :stdio,
  config: {
    command: "npm",
    args: ["--prefix", "examples/mcp_app/test_server", "run", "start:stdio"]
  }
)
```

Use `:ruby_llm` when you want full extension capability advertisement.  
`:mcp_sdk` accepts the same config but remains passive for extension advertisement.

## Step 3: Inspect MCP Apps Metadata

```ruby
tool = client.tool("render_items_embed")
puts tool.apps_metadata.resource_uri
puts tool.apps_metadata.visibility.inspect

resource = client.resource("ui_shell")
puts resource.apps_metadata.domain
puts resource.apps_metadata.permissions.inspect
```

These accessors normalize canonical and legacy metadata shapes.

## Step 4: Implement the Render/Action Loop

A clean MCP Apps pattern is:

1. Use one tool/resource to provide embeddable UI payloads (usually HTML or URI-based references).
2. Use separate tools for data mutations (`create`, `toggle`, `mark_done`, etc.).
3. Route UI events back to mutation tools, then re-fetch or patch UI state.

The local example at `examples/mcp_app` demonstrates this split:

- Server toolset in `examples/mcp_app/test_server/src/server.ts`
- Rails integration in `examples/mcp_app/rails_app/app/services/mcp_app_client.rb`
- UI wiring in `examples/mcp_app/rails_app/app/views/mcp_items/index.html.erb`

## Step 5: Keep Configuration Layered

Use global defaults, then override per client only when needed:

```ruby
RubyLLM::MCP.configure do |config|
  config.extensions.enable_apps
end

client = RubyLLM::MCP.client(
  name: "special-app-server",
  adapter: :ruby_llm,
  transport_type: :streamable,
  config: {
    url: "https://example.com/mcp",
    extensions: {
      "io.modelcontextprotocol/apps" => {
        "mimeTypes" => ["text/html;profile=mcp-app", "text/html"]
      }
    }
  }
)
```

RubyLLM MCP canonicalizes IDs and deep-merges client extension settings over global defaults.

## Common Pitfalls

- Putting `resourceUri` or `visibility` in `enable_apps` (those belong in tool `_meta.ui`)
- Expecting extension advertisement on protocol versions before `2025-06-18`
- Assuming `:mcp_sdk` advertises extension capabilities (it does not)

## Next Steps

- **[Client Extensions]({% link extensions/index.md %})** - Extension architecture and merge behavior
- **[MCP Apps]({% link extensions/mcp-apps.md %})** - Metadata mapping details
- **[Adapters & Transports]({% link guides/adapters.md %})** - Adapter mode comparison and transport strategy

## Working Example Application

This repository includes a working example application with MCP Apps support at `examples/mcp_app`.

![Working MCP Apps example application](/assets/images/mcp-app-working-example.png)
