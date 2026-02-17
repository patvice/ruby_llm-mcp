---
layout: default
title: MCP Apps
parent: Extensions
nav_order: 1
description: "MCP Apps extension support and metadata mapping in RubyLLM MCP"
---

# MCP Apps
{: .no_toc }

RubyLLM MCP supports MCP Apps through the UI extension capability and a metadata parsing layer on tools/resources/templates.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Capability Registration

Use the convenience helper to register the MCP Apps/UI extension:

```ruby
RubyLLM::MCP.configure do |config|
  config.extensions.enable_apps
end
```

By default this registers:

```ruby
"io.modelcontextprotocol/ui" => {
  "mimeTypes" => ["text/html;profile=mcp-app"]
}
```

You can override `mimeTypes`:

```ruby
RubyLLM::MCP.configure do |config|
  config.extensions.enable_apps(
    "mimeTypes" => ["text/html;profile=mcp-app", "text/html"]
  )
end
```

## Metadata Placement Rules

RubyLLM MCP keeps extension capability config separate from tool/resource metadata:

- Client capability fields such as `mimeTypes` belong in extension registration
- Tool UI fields such as `resourceUri` and `visibility` belong in tool `_meta.ui`

If you pass tool metadata fields to `enable_apps`, RubyLLM MCP raises an `ArgumentError` to prevent mixed concerns.

## Tool Metadata (`apps_metadata`)

Each `RubyLLM::MCP::Tool` exposes parsed MCP Apps metadata:

```ruby
tool = client.tool("render_widget")

tool.apps_metadata.resource_uri
tool.apps_metadata.visibility
tool.apps_metadata.model_visible?
tool.apps_metadata.app_visible?
```

Supported input forms:

- Canonical: `_meta.ui.resourceUri`
- Legacy alias: `_meta["ui/resourceUri"]`

If visibility is absent, RubyLLM MCP defaults it to `["model", "app"]`.

## Resource and Template Metadata (`apps_metadata`)

`RubyLLM::MCP::Resource` and `RubyLLM::MCP::ResourceTemplate` expose:

- `csp`
- `permissions`
- `domain`
- `prefers_border` (supports both `prefersBorder` and `prefers_border`)

Example:

```ruby
resource = client.resource("ui_shell")
meta = resource.apps_metadata

puts meta.domain
puts meta.permissions.inspect
```

## Adapter Notes

- `:ruby_llm` and `:mcp_sdk` both expose parsed `apps_metadata`
- Only `:ruby_llm` advertises extension capabilities in full mode
- `:mcp_sdk` remains passive for capability advertisement

## Practical Flow

1. Register UI extension capability (`enable_apps`)
2. Ensure server sends MCP Apps metadata in `_meta.ui`
3. Use RubyLLM MCP `apps_metadata` accessors to decide how to render/route UI content

For a hands-on implementation walkthrough, see **[MCP Apps]({% link guides/mcp-apps.md %})**.

## Working Example Application

This repository includes a working example application with MCP Apps support in `examples/mcp_app`.

![Working MCP Apps example application](/assets/images/mcp-app-working-example.png)
