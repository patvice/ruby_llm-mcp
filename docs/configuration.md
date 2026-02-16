---
layout: default
title: Configuration
nav_order: 2
description: "Advanced configuration options for RubyLLM MCP clients and transports"
---

# Configuration
{: .no_toc }

This covers all the configuration options available for RubyLLM MCP clients, including transport settings, connection options, and advanced features.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Global Configuration

Configure RubyLLM MCP globally before creating clients:

```ruby
RubyLLM::MCP.configure do |config|
  # Set logging options
  config.log_file = $stdout
  config.log_level = Logger::INFO

  # Or use a custom logger
  config.logger = Logger.new(STDOUT)

  # Paths to MCP servers
  config.mcps_config_path = "../mcps.yml"

  # Connection Pool for HTTP and SSE transports
  config.max_connections = 10
  config.pool_timeout = 5

  # Event handlers, these will be used for all clients, unless overridden on the client level
  config.on_progress do |progress|
    puts "Progress: #{progress}"
  end
  config.on_human_in_the_loop do |human_in_the_loop|
    puts "Human in the loop: #{human_in_the_loop}"
  end
  config.on_logging do |level, message|
    puts "Logging: #{level} - #{message}"
  end

  # Configure roots for filesystem access
  config.roots = ["/path/to/project", Rails.root]

  # Configure sampling
  # Enabled the clinet to support sampling requests,default: false
  config.sampling.enabled = true

  # Configure sampling preferred model
  config.sampling.preferred_model = "gpt-4"

  # Configure sampling guard, which can be used to filter out samples that are not wanted
  config.sampling.guard do |sample|
    sample.message.include?("Hello")
  end

  # Configure elicitation support (2025-06-18 protocol)
  config.on_elicitation do |elicitation|
    # Handle elicitation requests from MCP servers
    # Return structured response and true to accept
    puts "Server requests: #{elicitation.message}"
    elicitation.structured_response = { "response": "handled" }
    true
  end
end
```

## Adapter Selection

{: .label .label-green }
0.8+

RubyLLM MCP supports multiple SDK adapters. Choose between the native full-featured implementation or the official MCP SDK.

### Default Adapter

Set the default adapter for all clients:

```ruby
RubyLLM::MCP.configure do |config|
  # Options: :ruby_llm (default), :mcp_sdk
  config.default_adapter = :ruby_llm
end
```

### Adapter Options

**`:ruby_llm`** (default)
- Full MCP protocol implementation
- All transport types (stdio, SSE, HTTP)
- Advanced features (sampling, roots, progress tracking, etc.)

**`:mcp_sdk`**
- Official Anthropic-maintained SDK
- Core features (tools, resources, prompts, resource templates, logging)
- Limited advanced support (no sampling, roots, or other client-side advanced features)

See the [Adapters Guide]({% link guides/adapters.md %}) for detailed feature comparison and usage examples.

## Client Configuration

### Basic Client Options

All MCP clients support these common options:

```ruby
client = RubyLLM::MCP.client(
  name: "unique-client-name",          # Required: unique identifier
  transport_type: :stdio,              # Required: :stdio, :sse, or :streamable
  adapter: :ruby_llm,                  # Optional: :ruby_llm (default) or :mcp_sdk
  start: true,                         # Optional: auto-start connection (default: true)
  request_timeout: 8000,               # Optional: timeout in milliseconds (default: 8000)
  config: {                            # Required: transport-specific configuration
    # See transport sections below
  }
)
```

### Transport-Specific Configuration

#### STDIO Transport

Best for local MCP servers or command-line tools:

```ruby
client = RubyLLM::MCP.client(
  name: "local-server",
  transport_type: :stdio,
  config: {
    command: "python",                 # Required: command to run
    args: ["-m", "my_mcp_server"],    # Optional: command arguments
    env: {                            # Optional: environment variables
      "DEBUG" => "1",
      "PATH" => "/custom/path"
    }
  }
)
```

Common STDIO configurations:

```ruby
# Node.js MCP server
config: {
  command: "node",
  args: ["server.js"],
  env: { "NODE_ENV" => "production" }
}

# Python MCP server
config: {
  command: "python",
  args: ["-m", "mcp_server"],
  env: { "PYTHONPATH" => "/path/to/modules" }
}

# NPX package
config: {
  command: "npx",
  args: ["@modelcontextprotocol/server-filesystem", "/path/to/directory"]
}
```

#### SSE Transport

Best for web-based MCP servers using Server-Sent Events:

```ruby
client = RubyLLM::MCP.client(
  name: "web-server",
  adapter: :ruby_llm,  # Optional; :mcp_sdk also supports SSE
  transport_type: :sse,
  config: {
    url: "https://api.example.com/mcp/sse",  # Required: SSE endpoint
    headers: {                               # Optional: HTTP headers
      "Authorization" => "Bearer #{ENV['API_TOKEN']}",
      "User-Agent" => "MyApp/1.0"
    }
  }
)
```

#### Streamable HTTP Transport

Best for HTTP-based MCP servers that support streaming:

```ruby
client = RubyLLM::MCP.client(
  name: "streaming-server",
  transport_type: :streamable,
  config: {
    url: "https://api.example.com/mcp",      # Required: HTTP endpoint
    headers: {                               # Optional: HTTP headers
      "Authorization" => "Bearer #{ENV['API_TOKEN']}",
      "Content-Type" => "application/json"
    }
  }
)
```

## Advanced Configuration

### Request Timeout

Control how long to wait for responses:

```ruby
client = RubyLLM::MCP.client(
  name: "slow-server",
  transport_type: :stdio,
  request_timeout: 30000,  # 30 seconds
  config: { command: "slow-mcp-server" }
)
```

### Manual Connection Control

Create clients without auto-starting:

```ruby
client = RubyLLM::MCP.client(
  name: "manual-server",
  transport_type: :stdio,
  start: false,  # Don't start automatically
  config: { command: "mcp-server" }
)

# Start when ready
client.start

# Check status
puts client.alive?

# Restart if needed
client.restart!

# Stop when done
client.stop
```

## Logging Configuration

### Basic Logging

```ruby
RubyLLM::MCP.configure do |config|
  config.log_file = $stdout
  config.log_level = Logger::INFO
end
```

### Custom Logger

```ruby
# File-based logging
logger = Logger.new("mcp.log")
logger.level = Logger::DEBUG

RubyLLM::MCP.configure do |config|
  config.logger = logger
end
```

### Log Levels

Available log levels:

- `Logger::DEBUG` - Detailed debugging information
- `Logger::INFO` - General information
- `Logger::WARN` - Warning messages
- `Logger::ERROR` - Error messages only
- `Logger::FATAL` - Fatal errors only

## Sampling Configuration

Enable MCP servers to use your LLM for their own requests:

```ruby
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true
  config.sampling.preferred_model = "gpt-4"

  # Or use dynamic model selection
  config.sampling.preferred_model do |model_preferences|
    # Use the server's preferred model if available
    model_preferences.hints.first || "gpt-4"
  end

  # Add guards to control what gets processed
  config.sampling.guard do |sample|
    # Only allow samples containing "Hello"
    sample.message.include?("Hello")
  end
end
```

## Roots Configuration

Provide filesystem access to MCP servers:

```ruby
RubyLLM::MCP.configure do |config|
  config.roots = [
    "/path/to/project",
    Rails.root,
    Pathname.new("/another/path")
  ]
end

# Access roots in your client
client = RubyLLM::MCP.client(...)
puts client.roots.paths
# => ["/path/to/project", "/path/to/rails/root", "/another/path"]

# Modify roots at runtime
client.roots.add("/new/path")
client.roots.remove("/old/path")
```

## Elicitation Configuration

Configure how your client handles elicitation requests from servers:

```ruby
RubyLLM::MCP.configure do |config|
  # Global elicitation handler
  config.on_elicitation do |elicitation|
    puts "Server message: #{elicitation.message}"

    # Auto-approve simple requests
    if elicitation.message.include?("confirmation")
      elicitation.structured_response = { "confirmed": true }
      true
    else
      # Reject complex requests
      false
    end
  end
end

# Or configure per-client
client.on_elicitation do |elicitation|
  # Interactive handler
  puts elicitation.message
  puts "Expected response format: #{elicitation.requested_schema}"

  # Collect user input
  response = collect_user_response(elicitation.requested_schema)
  elicitation.structured_response = response
  true
end
```

### OAuth Authentication

Configure OAuth for Streamable HTTP transport:

```ruby
client = RubyLLM::MCP.client(
  name: "oauth-server",
  transport_type: :streamable,
  config: {
    url: "https://api.example.com/mcp",
    oauth: {
      issuer: ENV['OAUTH_ISSUER'],
      client_id: ENV['OAUTH_CLIENT_ID'],
      client_secret: ENV['OAUTH_CLIENT_SECRET'],
      scope: "mcp:read mcp:write"
    }
  }
)
```

## Protocol Version Configuration

You can configure which MCP protocol version the client should use when connecting to servers. This is useful for testing newer protocol features or ensuring compatibility with specific server versions.

### Setting Protocol Version in Transport Config

```ruby
# Force client to use a specific protocol version
client = RubyLLM::MCP::Client.new(
  name: "my-server",
  transport_type: :stdio,
  config: {
    command: ["node", "server.js"],
    protocol_version: "2025-06-18"  # Override default version
  }
)
```

### Available Protocol Versions

The RubyLLM MCP client supports multiple protocol versions. You can access these through the protocol constants:

```ruby
# Latest supported protocol version
puts RubyLLM::MCP::Native::Protocol.latest_version
# => "2025-06-18"

# Default version used for negotiation
puts RubyLLM::MCP::Native::Protocol.default_negotiated_version
# => "2025-03-26"

# All supported versions
puts RubyLLM::MCP::Native::Protocol.supported_versions
# => ["2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07"]

# Check if a version is supported
RubyLLM::MCP::Native::Protocol.supported_version?("2025-06-18")
# => true
```

### Protocol Version Features

Different protocol versions support different features:

- **2025-06-18** (Latest): Structured tool output, OAuth authentication, elicitation support, resource links, enhanced metadata
- **2025-03-26** (Default): Tool calling, resources, prompts, completions, notifications
- **2024-11-05**: Basic tool and resource support
- **2024-10-07**: Initial MCP implementation

### Enhanced Metadata Support

Progress tracking automatically includes metadata when enabled:

```ruby
RubyLLM::MCP.configure do |config|
  # Enable progress tracking with metadata
  config.on_progress do |progress|
    puts "Operation ID: #{progress.operation_id}"
    puts "Progress: #{progress.progress}%"
    puts "Metadata: #{progress.metadata}"
  end
end

# Tool calls will automatically include progress tokens
client = RubyLLM::MCP.client(...)
tool = client.tool("long_operation")
result = tool.execute(data: "large_dataset")  # Includes progress metadata
```

## Error Handling Configuration

### Timeout Handling

```ruby
client = RubyLLM::MCP.client(
  name: "timeout-server",
  transport_type: :stdio,
  request_timeout: 5000,
  config: { command: "slow-server" }
)

begin
  result = client.execute_tool(name: "slow_tool", parameters: {})
rescue RubyLLM::MCP::Errors::TimeoutError => e
  puts "Request timed out: #{e.message}"
end
```

### Connection Error Handling

```ruby
begin
  client = RubyLLM::MCP.client(
    name: "failing-server",
    transport_type: :stdio,
    config: { command: "nonexistent-command" }
  )
rescue RubyLLM::MCP::Errors::TransportError => e
  puts "Failed to start server: #{e.message}"
end
```

## Next Steps

- **[Tools]({% link server/tools.md %})** - Working with MCP tools
- **[Resources]({% link server/resources.md %})** - Managing resources and templates
- **[Rails Integration]({% link guides/rails-integration.md %})** - Using MCP with Rails
