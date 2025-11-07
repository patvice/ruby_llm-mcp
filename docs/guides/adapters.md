---
layout: default
title: Adapters
parent: Guides
nav_order: 5
description: "Understanding and using MCP adapters in RubyLLM"
---

# Adapters
{: .no_toc }

{: .label .label-green }
0.8+

Starting with version 0.8.0, RubyLLM MCP supports multiple SDK adapters, allowing you to choose between the native full-featured implementation or the official MCP SDK.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The adapter pattern in RubyLLM MCP allows you to choose which SDK implementation powers your MCP clients. This gives you flexibility to:

- Use the native `:ruby_llm` adapter for full MCP feature support build inside the gem
- Use the official `:mcp_sdk` adapter (still under development, but making great progress)
- Mix both adapters in the same application for different servers

## Available Adapters

### RubyLLM Adapter (`:ruby_llm`)

The default, full-featured adapter that implements the complete MCP protocol with extensions.

**When to use:**
- You need advanced features like sampling, roots, or progress tracking
- You want SSE transport support
- You need human-in-the-loop approvals
- You're using elicitation for interactive workflows

**Advantages:**
- Complete MCP protocol implementation
- All transport types supported
- Additional features beyond core spec
- Optimized for RubyLLM integration

### MCP SDK Adapter (`:mcp_sdk`)

Wraps the official MCP SDK maintained by Anthropic.

**When to use:**
- You prefer the official Anthropic-maintained implementation
- You only need core MCP features (tools, resources, prompts)
- You want to ensure compatibility with the reference implementation

**Advantages:**
- Official Anthropic support
- Reference implementation compatibility
- Simpler, focused feature set

## Feature Comparison

| Feature | RubyLLM Adapter | MCP SDK Adapter |
|---------|-----------------|-----------------|
| **Core Features** |
| Tools (list/call) | ✅ | ✅ |
| Resources (list/read) | ✅ | ✅ |
| Prompts (list/get) | ✅ | ❌ |
| Resource Templates | ✅ | ❌ |
| **Transports** |
| stdio | ✅ | ✅ |
| HTTP/Streamable | ✅ | ✅ |
| SSE | ✅ | ✅ |
| **Advanced Features** |
| Completions | ✅ | ❌ |
| Logging | ✅ | ❌ |
| Sampling | ✅ | ❌ |
| Roots | ✅ | ❌ |
| Notifications | ✅ | ❌ |
| Progress Tracking | ✅ | ❌ |
| Human-in-the-Loop | ✅ | ❌ |
| Elicitation | ✅ | ❌ |
| Resource Subscriptions | ✅ | ❌ |

## Transport Compatibility

Custom transports are implemented by the adapter and are not part of the official MCP SDK and are based on the native transports.

| Transport | RubyLLM Adapter | MCP SDK Adapter |
|-----------|-----------------|-----------------|
| `:stdio` | ✅ | Custom |
| `:http` | ✅ | ✅ |
| `:streamable` | ✅ | Custom |
| `:streamable_http` | ✅ | Custom |
| `:sse` | ✅ | Custom |

## Configuration

### Global Default Adapter

Set the default adapter for all clients in your configuration:

```ruby
RubyLLM::MCP.configure do |config|
  config.default_adapter = :ruby_llm  # or :mcp_sdk
end
```

### Per-Client Adapter

Override the adapter for individual clients:

```ruby
# Using RubyLLM adapter
client = RubyLLM::MCP.client(
  name: "filesystem",
  adapter: :ruby_llm,
  transport_type: :stdio,
  config: {
    command: "npx",
    args: ["@modelcontextprotocol/server-filesystem", "/path"]
  }
)

# Using MCP SDK adapter
client = RubyLLM::MCP.client(
  name: "weather",
  adapter: :mcp_sdk,
  transport_type: :http,
  config: {
    url: "https://api.example.com/mcp"
  }
)
```

### YAML Configuration

In `config/mcps.yml`:

```yaml
mcp_servers:
  filesystem:
    adapter: ruby_llm
    transport_type: stdio
    command: npx
    args:
      - "@modelcontextprotocol/server-filesystem"
      - "/path/to/directory"

  api_server:
    adapter: mcp_sdk
    transport_type: http
    url: "https://api.example.com/mcp"
    headers:
      Authorization: "Bearer <%= ENV['API_KEY'] %>"
```

## Using the MCP SDK Adapter

### Installation

The official MCP SDK is an optional dependency. Add it to your Gemfile when using the `:mcp_sdk` adapter:

```ruby
gem 'ruby_llm-mcp', '~> 0.8'
gem 'mcp', '~> 0.4'  # Required for mcp_sdk adapter
```

Then run:

```bash
bundle install
```

### Basic Usage

```ruby
# Configure to use MCP SDK
client = RubyLLM::MCP.client(
  name: "my_server",
  adapter: :mcp_sdk,
  transport_type: :stdio,
  config: {
    command: "python",
    args: ["-m", "my_mcp_server"]
  }
)

# Core features work the same
tools = client.tools
resources = client.resources
prompts = client.prompts

# Call tools normally
tool = client.tool("calculator")
result = tool.execute(operation: "add", a: 5, b: 3)
```

### SSE Transport

The `:mcp_sdk` adapter supports SSE (Server-Sent Events) transport for HTTP-based servers:

```ruby
# Configure MCP SDK with SSE transport
client = RubyLLM::MCP.client(
  name: "remote_server",
  adapter: :mcp_sdk,
  transport_type: :sse,
  config: {
    url: "https://api.example.com/mcp/sse",
    headers: {
      "Authorization" => "Bearer #{ENV['API_KEY']}"
    }
  }
)

# Use the client normally
tools = client.tools
tool = client.tool("process_data")
result = tool.execute(data: "example")
```

In YAML configuration:

```yaml
mcp_servers:
  remote_sse_server:
    adapter: mcp_sdk
    transport_type: sse
    url: "https://api.example.com/mcp/sse"
    headers:
      Authorization: "Bearer <%= ENV['API_KEY'] %>"
```

### Feature Limitations

When using `:mcp_sdk`, attempting to use unsupported features will raise helpful errors:

```ruby
client = RubyLLM::MCP.client(
  name: "server",
  adapter: :mcp_sdk,
  transport_type: :stdio,
  config: { command: "server" }
)

# This will raise UnsupportedFeature error
client.on_progress do |progress|
  # Progress tracking not available in mcp_sdk
end
# => RubyLLM::MCP::Errors::UnsupportedFeature:
#    Feature 'progress_tracking' is not supported by the mcp_sdk adapter.
#    This feature requires the :ruby_llm adapter.
```

## Mixed Adapter Usage

You can use different adapters for different servers in the same application:

```ruby
RubyLLM::MCP.configure do |config|
  config.default_adapter = :ruby_llm

  config.mcp_configuration = [
    # Use RubyLLM adapter for local filesystem (needs roots)
    {
      name: "filesystem",
      adapter: :ruby_llm,
      transport_type: :stdio,
      config: {
        command: "npx",
        args: ["@modelcontextprotocol/server-filesystem", Rails.root]
      }
    },
    # Use MCP SDK for external API (simple HTTP)
    {
      name: "weather",
      adapter: :mcp_sdk,
      transport_type: :http,
      config: {
        url: "https://weather-api.example.com/mcp"
      }
    }
  ]
end

# Both clients work together
RubyLLM::MCP.establish_connection do |clients|
  fs_client = clients["filesystem"]   # Using ruby_llm adapter
  weather_client = clients["weather"] # Using mcp_sdk adapter

  # Both provide tools to RubyLLM
  all_tools = RubyLLM::MCP.tools
end
```

## Best Practices

### Choosing an Adapter

1. **Start with `:ruby_llm`** if you're unsure - it supports all features
2. **Use `:mcp_sdk`** when you specifically need the official implementation
3. **Check feature requirements** before choosing an adapter
4. **Consider transport needs** - SSE requires `:ruby_llm`

### Performance Considerations

- Both adapters have similar performance for core operations
- `:ruby_llm` has additional overhead for advanced features when enabled
- `:mcp_sdk` is lighter if you only need core functionality

### Upgrading from 0.7

If you're upgrading from version 0.7:

1. The default adapter is `:ruby_llm` - no changes needed for existing code
2. All existing features continue to work as before
3. Optionally migrate specific clients to `:mcp_sdk` if desired

See the [Upgrading from 0.7 to 0.8]({% link guides/upgrading-0.7-to-0.8.md %}) guide for detailed migration steps.

## Troubleshooting

### "Feature not supported" errors

If you see errors about unsupported features:

1. Check which adapter you're using
2. Verify the feature is supported (see feature comparison table)
3. Switch to `:ruby_llm` adapter if you need the feature

### "Transport not supported" errors

If you see transport errors:

1. Verify the transport is compatible with your adapter
2. SSE only works with `:ruby_llm`
3. Use `:stdio` or `:http` for maximum compatibility

### Missing MCP gem

If you see "LoadError: cannot load such file -- mcp":

1. Add `gem 'mcp', '~> 0.4'` to your Gemfile
2. Run `bundle install`
3. This is only needed when using `adapter: :mcp_sdk`

## Next Steps

- **[Configuration]({% link configuration.md %})** - Detailed configuration options
- **[Tools]({% link server/tools.md %})** - Working with MCP tools
- **[Resources]({% link server/resources.md %})** - Managing resources
- **[Upgrading]({% link guides/upgrading-0.7-to-0.8.md %})** - Migration guide
