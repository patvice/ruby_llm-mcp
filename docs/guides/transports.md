---
layout: default
title: Transports
parent: Guides
nav_order: 10
description: "Understanding MCP transports and building custom transport implementations"
---

# Transports
{: .no_toc }

MCP transports are the communication layer between your Ruby client and MCP servers. This guide covers the built-in transport types and how to create custom transport implementations for specialized use cases.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Transports handle the actual communication protocol between the MCP client and server. They are responsible for:

- Establishing connections
- Sending requests and receiving responses
- Managing the connection lifecycle
- Handling protocol-specific details

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
    headers: { "Content-Type" => "application/json" }
  }
)
```

**Use cases:**

- REST API-based MCP servers
- HTTP-first architectures
- Cloud-based MCP services

## Transport Interface

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

## Creating Custom Transports

### Basic Custom Transport

Here's a template for creating a custom transport:

```ruby
class MyCustomTransport
  def initialize(coordinator:, **config)
    @coordinator = coordinator
    @config = config
    @connection = nil
    @protocol_version = nil
  end

  def request(body, add_id: true, wait_for_response: true)
    # Add request ID if needed
    if add_id
      body = body.merge("id" => generate_request_id)
    end

    # Send the request
    response_data = send_request(body)

    # Create result object
    result = RubyLLM::MCP::Result.new(response_data)

    # Let coordinator process the result
    @coordinator.process_result(result)

    # Return result if it's not a notification
    return nil if result.notification?

    result
  end

  def alive?
    @connection && @connection.connected?
  end

  def start
    @connection = establish_connection
    perform_handshake if @connection
  end

  def close
    @connection&.close
    @connection = nil
  end

  def set_protocol_version(version)
    @protocol_version = version
  end

  private

  def establish_connection
    # Implementation specific
  end

  def send_request(body)
    # Implementation specific
  end

  def generate_request_id
    SecureRandom.uuid
  end

  def perform_handshake
    # Optional: perform any connection setup
  end
end
```

## Registering Custom Transports

Once you've created a custom transport, register it with the transport factory:

```ruby
# Register your custom transport
RubyLLM::MCP::Transport.register_transport(:websocket, WebSocketTransport)
RubyLLM::MCP::Transport.register_transport(:redis_pubsub, RedisPubSubTransport)

# Now you can use it
client = RubyLLM::MCP.client(
  name: "websocket-server",
  transport_type: :websocket,
  config: {
    url: "ws://localhost:8080/mcp",
    headers: { "Authorization" => "Bearer token" }
  }
)
```

## Next Steps

- **[Configuration]({% link configuration.md %})** - Advanced client configuration
- **[Tools]({% link server/tools.md %})** - Working with MCP tools
- **[Notifications]({% link server/notifications.md %})** - Handling real-time updates
