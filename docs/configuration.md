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
  # Enable complex parameter support
  config.support_complex_parameters!

  # Set logging options
  config.log_file = $stdout
  config.log_level = Logger::INFO

  # Or use a custom logger
  config.logger = Logger.new(STDOUT)

  # Configure roots for filesystem access
  config.roots = ["/path/to/project", Rails.root]

  # Configure sampling
  config.sampling.enabled = true
  config.sampling.preferred_model = "gpt-4"
end
```

## Client Configuration

### Basic Client Options

All MCP clients support these common options:

```ruby
client = RubyLLM::MCP.client(
  name: "unique-client-name",          # Required: unique identifier
  transport_type: :stdio,              # Required: :stdio, :sse, or :streamable
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

### Complex Parameter Support

Enable support for complex parameters like arrays and nested objects:

```ruby
RubyLLM::MCP.configure do |config|
  config.support_complex_parameters!
end

# Now you can use complex parameters in tools
result = client.execute_tool(
  name: "complex_tool",
  parameters: {
    items: [
      { name: "item1", value: 100 },
      { name: "item2", value: 200 }
    ],
    options: {
      sort: true,
      filter: { category: "active" }
    }
  }
)
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

## Environment-Specific Configuration

### Development Configuration

```ruby
if Rails.env.development?
  RubyLLM::MCP.configure do |config|
    config.log_level = Logger::DEBUG
    config.sampling.enabled = true
    config.roots = [Rails.root]
  end
end
```

### Production Configuration

```ruby
if Rails.env.production?
  RubyLLM::MCP.configure do |config|
    config.log_level = Logger::ERROR
    config.logger = Logger.new("/var/log/mcp.log")
    config.sampling.enabled = false
  end
end
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

## Configuration Best Practices

### 1. Use Environment Variables

```ruby
client = RubyLLM::MCP.client(
  name: "api-server",
  transport_type: :sse,
  config: {
    url: ENV.fetch("MCP_SERVER_URL"),
    headers: {
      "Authorization" => "Bearer #{ENV.fetch('MCP_API_TOKEN')}"
    }
  }
)
```

### 2. Validate Configuration

```ruby
def create_mcp_client(name, config)
  required_keys = %w[url headers]
  missing_keys = required_keys - config.keys

  raise ArgumentError, "Missing keys: #{missing_keys}" unless missing_keys.empty?

  RubyLLM::MCP.client(
    name: name,
    transport_type: :sse,
    config: config
  )
end
```

### 3. Use Separate Configurations

```ruby
# config/mcp.yml
development:
  filesystem:
    transport_type: stdio
    command: npx
    args: ["@modelcontextprotocol/server-filesystem", "."]

production:
  api_server:
    transport_type: sse
    url: "https://api.example.com/mcp/sse"
    headers:
      Authorization: "Bearer <%= ENV['API_TOKEN'] %>"
```

### 4. Connection Pooling

```ruby
class MCPClientPool
  def initialize(configs)
    @clients = configs.map do |name, config|
      [name, RubyLLM::MCP.client(name: name, **config)]
    end.to_h
  end

  def client(name)
    @clients[name] || raise("Client #{name} not found")
  end

  def all_tools
    @clients.values.flat_map(&:tools)
  end
end
```

## Next Steps

- **[Tools]({% link server/tools.md %})** - Working with MCP tools
- **[Resources]({% link server/resources.md %})** - Managing resources and templates
- **[Rails Integration]({% link guides/rails-integration.md %})** - Using MCP with Rails
