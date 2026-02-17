---
layout: default
title: Extensions
parent: Core Features
nav_order: 3
description: "How extension capabilities are configured, merged, and negotiated in RubyLLM MCP"
has_children: true
permalink: /extensions/
---

# Extensions
{: .no_toc }

Extensions let your MCP client advertise optional capabilities to servers through `capabilities.extensions`.

In RubyLLM MCP, extensions are configured in one place and then merged into each client session with deterministic rules.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Core Model

RubyLLM MCP implements extensions with three core pieces:

1. **Extension Registry** - canonicalizes IDs and merges global + per-client values
2. **Configuration API** - `config.extensions.register(...)` and `config.extensions.enable_apps(...)`
3. **Adapter behavior** - controls whether extension capabilities are actively advertised

## Extension IDs and Alias Handling

RubyLLM MCP normalizes extension IDs before storage and merge.

- Canonical MCP Apps/UI ID: `io.modelcontextprotocol/ui`
- Accepted alias: `io.modelcontextprotocol/apps`
- Outbound client capability advertisement always uses canonical ID

This means you can configure either ID and still get stable merged output.

## Configuration Surfaces

### Global

```ruby
RubyLLM::MCP.configure do |config|
  config.extensions.register(
    "io.modelcontextprotocol/ui",
    "mimeTypes" => ["text/html;profile=mcp-app"]
  )
end
```

### Per-client override

```ruby
client = RubyLLM::MCP.client(
  name: "server",
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

Per-client values are merged over global values. Nested hashes are deep-merged.

## Negotiation Rules

Extension advertisement is protocol-version aware.

- `2025-03-26` and older: extensions are not advertised
- `2025-06-18` and draft (`2026-01-26`): extensions are advertised when adapter supports full mode

## Adapter Modes

- `:ruby_llm` adapter: **full** extension mode (`capabilities.extensions` advertised when protocol supports it)
- `:mcp_sdk` adapter: **passive** extension mode (config accepted, metadata parsing still works, no extension capability advertisement)

## Next Steps

- **[MCP Apps]({% link extensions/mcp-apps.md %})** - UI extension details and metadata layout
- **[Configuration]({% link configuration.md %})** - Full config reference, including protocol track/version controls
