---
layout: default
title: Adapters & Transports
parent: Guides
nav_order: 4
description: "Understanding MCP adapters, transports, and building custom transport implementations"
---

# Adapters & Transports
{: .no_toc }

{: .label .label-green }
1.0+

RubyLLM MCP 1.0 provides a mature, stable adapter system with multiple SDK implementations and transport types, giving you complete control over how your application communicates with MCP servers.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

RubyLLM MCP provides two key architectural components:

**Adapters** - Choose which SDK implementation powers your MCP clients:
- Use the native `:ruby_llm` adapter for full MCP feature support built inside the gem
- Use the official `:mcp_sdk` adapter maintained by Anthropic (requires Ruby 3.1+)
- Mix both adapters in the same application for different servers

**Transports** - Handle the communication layer between your Ruby client and MCP servers:
- Establish connections
- Send requests and receive responses
- Manage the connection lifecycle
- Handle protocol-specific details

## Available Adapters

### RubyLLM Adapter (`:ruby_llm`)

The default, full-featured adapter that implements the complete MCP protocol with extensions.

**Key Features:**
- ✅ Complete MCP protocol implementation with advanced features (sampling, roots, progress tracking, elicitation)
- ✅ Experimental task lifecycle support (`tasks/list`, `tasks/get`, `tasks/result`, `tasks/cancel`)
- ✅ All transport types supported (stdio, SSE, streamable HTTP)
- ✅ **Custom transport support** - Register and use your own transport implementations
- ✅ Ruby 2.7+ compatible

**Best for:** Full-featured MCP integrations, custom transport requirements, and advanced protocol features.

### MCP SDK Adapter (`:mcp_sdk`)

Wraps the official MCP SDK maintained by Anthropic.

{: .important }
> **Ruby 3.1+ Required**
> The official `mcp` gem requires Ruby 2.7+, and RubyLLM MCP requires Ruby 3.1.3+. If you're using an older Ruby version, use the `:ruby_llm` adapter instead.

**Key Features:**
- ✅ Official Anthropic-maintained implementation
- ✅ Core MCP features (tools, resources, prompts, resource templates, logging)
- ✅ Basic transports (stdio, HTTP) with custom wrapper support
- ⚠️ No custom transport registration - requires Ruby 3.1+

**Best for:** Reference implementation compatibility and core MCP features only.

## Feature Comparison

| Feature | RubyLLM Adapter | MCP SDK Adapter |
|---------|-----------------|-----------------|
| **Core Features** |
| Tools (list/call) | ✅ | ✅ |
| Resources (list/read) | ✅ | ✅ |
| Prompts (list/get) | ✅ | ✅ |
| Resource Templates | ✅ | ✅ |
| **Transports** |
| stdio | ✅ | ✅ |
| HTTP/Streamable | ✅ | ✅ |
| SSE | ✅ | ✅ |
| **Advanced Features** |
| Completions | ✅ | ❌ |
| Logging | ✅ | ✅ |
| Sampling | ✅ | ❌ |
| Roots | ✅ | ❌ |
| Notifications | ✅ | ❌ |
| Progress Tracking | ✅ | ❌ |
| Human-in-the-Loop | ✅ | ❌ |
| Elicitation | ✅ | ❌ |
| Tasks | ✅ | ❌ |
| Resource Subscriptions | ✅ | ❌ |

Task support in the `:ruby_llm` adapter is experimental and subject to change in both the MCP spec and this gem implementation.

## Transport Compatibility

Custom transports are implemented by the adapter and are not part of the official MCP SDK and are based on the native transports.

| Transport | RubyLLM Adapter | MCP SDK Adapter |
|-----------|-----------------|-----------------|
| `:stdio` | ✅ | Custom |
| `:http` | ✅ | ✅ |
| `:streamable` | ✅ | Custom |
| `:streamable_http` | ✅ | Custom |
| `:sse` | ✅ | Custom |

---

## Built-in Transport Types

### STDIO Transport

Best for local MCP servers that communicate via standard input/output:

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

**Use cases:**

- Local development
- Command-line MCP servers
- Subprocess-based servers

### SSE Transport (Server-Sent Events)

Best for web-based MCP servers using HTTP with server-sent events:

```ruby
client = RubyLLM::MCP.client(
  name: "web-server",
  transport_type: :sse,
  config: {
    url: "https://api.example.com/mcp/sse",
    version: :http2, # You can force HTTP/1.1 by setting this to :http1, default will try to setup HTTP/2 connection
    headers: { "Authorization" => "Bearer token" }
  }
)
```

**Use cases:**

- Web-based MCP services
- Real-time communication needs
- HTTP-based infrastructure

### Streamable HTTP Transport

Best for HTTP-based MCP servers that support streaming responses:

```ruby
client = RubyLLM::MCP.client(
  name: "streaming-server",
  transport_type: :streamable,
  config: {
    url: "https://api.example.com/mcp",
    version: :http2, # You can force HTTP/1.1 by setting this to :http1, default will try to setup HTTP/2 connection
    headers: { "Content-Type" => "application/json" }
  }
)
```

#### OAuth Authentication

{: .new }
OAuth authentication was introduced in MCP Protocol 2025-06-18 for Streamable HTTP transport.

For servers requiring OAuth authentication:

```ruby
client = RubyLLM::MCP.client(
  name: "oauth-server",
  transport_type: :streamable,
  config: {
    url: "https://api.example.com/mcp",
    oauth: {
      issuer: "https://oauth.provider.com",
      client_id: "your-client-id",
      client_secret: "your-client-secret",
      scope: "mcp:read mcp:write"  # Optional
    }
  }
)
```

**OAuth Configuration:**

| Option | Description | Required |
|--------|-------------|----------|
| `issuer` | OAuth provider's issuer URL | Yes |
| `client_id` | OAuth client identifier | Yes |
| `client_secret` | OAuth client secret | Yes |
| `scope` | Requested OAuth scopes | No |

The client automatically handles token acquisition, refresh, and authorization headers.

**Use cases:**

- REST API-based MCP servers
- HTTP-first architectures
- Cloud-based MCP services
- Enterprise servers requiring OAuth

---

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

{: .warning }
> **Ruby 3.1+ Required**
> The official `mcp` gem supports Ruby 2.7+, and RubyLLM MCP supports Ruby 3.1.3+.

The official MCP SDK is an optional dependency. Add it to your Gemfile when using the `:mcp_sdk` adapter:

```ruby
gem 'ruby_llm-mcp', '~> 1.0'
gem 'mcp', '~> 0.7'  # Required for mcp_sdk adapter
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

---

## Custom Transports

{: .label .label-blue }
RubyLLM Adapter Only

The `:ruby_llm` adapter supports registering custom transport implementations, allowing you to extend the gem with your own communication protocols.

### Transport Interface

All transport implementations must implement the following interface:

```ruby
class CustomTransport
  # Initialize the transport
  def initialize(coordinator:, **config)
    @coordinator = coordinator
    @config = config
  end

  # Send a request and optionally wait for response
  def request(body, add_id: true, wait_for_response: true)
    # Implementation specific
  end

  # Check if transport is alive/connected
  def alive?
    # Implementation specific
  end

  # Start the transport connection
  def start
    # Implementation specific
  end

  # Close the transport connection
  def close
    # Implementation specific
  end

  # Set the MCP protocol version
  def set_protocol_version(version)
    @protocol_version = version
  end
end
```

### Registering Custom Transports

Once you've created a custom transport, register it with the transport factory:

```ruby
# Register your custom transport
RubyLLM::MCP::Native::Transport.register_transport(:websocket, WebSocketTransport)
RubyLLM::MCP::Native::Transport.register_transport(:redis_pubsub, RedisPubSubTransport)

# Now you can use it with any client using the ruby_llm adapter
client = RubyLLM::MCP.client(
  name: "websocket-server",
  adapter: :ruby_llm,  # Custom transports only work with ruby_llm adapter
  transport_type: :websocket,
  config: {
    url: "ws://localhost:8080/mcp",
    headers: { "Authorization" => "Bearer token" }
  }
)
```

---

## Best Practices

### Choosing an Adapter

1. **Start with `:ruby_llm`** if you're unsure - it supports all features
2. **Use `:mcp_sdk`** when you specifically need the official implementation
3. **Check feature requirements** before choosing an adapter
4. **Consider transport and feature needs** - advanced client features still require `:ruby_llm`
5. **Check Ruby version** - `:mcp_sdk` requires Ruby 3.1+

### Upgrading from 1.0

If you're upgrading from version 1.0:

1. The default adapter is `:ruby_llm` - no changes needed for existing code
2. All existing features continue to work as before
3. Optionally migrate specific clients to `:mcp_sdk` if desired


## Troubleshooting

### "Feature not supported" errors

If you see errors about unsupported features:

1. Check which adapter you're using
2. Verify the feature is supported (see feature comparison table)
3. Switch to `:ruby_llm` adapter if you need the feature

### "Transport not supported" errors

If you see transport errors:

1. Verify the transport is compatible with your adapter
2. Prefer `:stdio` or `:streamable` for maximum compatibility
3. Use `:http` for simple JSON request/response servers

### Missing MCP gem

If you see "LoadError: cannot load such file -- mcp":

1. Add `gem 'mcp', '~> 0.7'` to your Gemfile
2. Run `bundle install`
3. Ensure you're running Ruby 3.1 or higher
4. This is only needed when using `adapter: :mcp_sdk`

### Ruby Version Compatibility

If you encounter issues with the `:mcp_sdk` adapter:

1. Check your Ruby version: `ruby -v`
2. The `mcp` gem requires Ruby 2.7 or higher (RubyLLM MCP requires 3.1.3+)
3. Switch to `:ruby_llm` adapter if you're on an older Ruby version
4. Consider upgrading Ruby if you need the official SDK

## Next Steps

- **[Configuration]({% link configuration.md %})** - Detailed configuration options
- **[Getting Started]({% link guides/getting-started.md %})** - Quick start guide
- **[Tools]({% link server/tools.md %})** - Working with MCP tools
- **[Resources]({% link server/resources.md %})** - Managing resources
- **[Notifications]({% link server/notifications.md %})** - Handling real-time updates
- **[Upgrading from 0.8 to 1.0]({% link guides/upgrading-0.8-to-1.0.md %})** - Migration guide
