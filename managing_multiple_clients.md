# Managing Multiple MCP Clients

This document explains how applications can take advantage of the enhanced client management capabilities in RubyLLM::MCP to handle multiple MCP clients simultaneously.

## Overview

The `RubyLLM::MCP.client` method now creates a new client instance on each call, enabling external applications to manage multiple MCP clients with different configurations and purposes.

## Key Changes

**Before:** The `client` method used memoization (`@client ||= Client.new`), returning the same instance on repeated calls.

**After:** The `client` method creates a new instance each time (`@client = Client.new`), allowing external management of multiple clients.

## Basic Usage Pattern

### Simple Multiple Client Creation

```ruby
# Create different clients for different purposes
github_client = RubyLLM::MCP.client(
  name: "github",
  transport_type: "sse",
  config: { url: "https://github-mcp-server.example.com" }
)

filesystem_client = RubyLLM::MCP.client(
  name: "filesystem", 
  transport_type: "stdio",
  config: { command: "mcp-server-filesystem", args: ["/path/to/files"] }
)

database_client = RubyLLM::MCP.client(
  name: "database",
  transport_type: "stdio", 
  config: { command: "mcp-server-database", args: ["--connection-string", "..."] }
)
```

### Client Manager Pattern

For more sophisticated management, create a client manager class:

```ruby
class MCPClientManager
  def initialize
    @clients = {}
  end
  
  def add_client(name, **config)
    @clients[name] = RubyLLM::MCP.client(**config)
  end
  
  def get_client(name)
    @clients[name]
  end
  
  def remove_client(name)
    client = @clients.delete(name)
    client&.stop  # Properly close the client
    client
  end
  
  def clients
    @clients.dup
  end
  
  def client_names
    @clients.keys
  end
  
  def stop_all
    @clients.each_value(&:stop)
    @clients.clear
  end
end
```

## Advanced Usage Examples

### Configuration-Based Client Setup

```ruby
# Define client configurations
CLIENTS_CONFIG = {
  github: {
    name: "github",
    transport_type: "sse",
    config: { url: "https://github-mcp-server.example.com" }
  },
  filesystem: {
    name: "filesystem",
    transport_type: "stdio", 
    config: { command: "mcp-server-filesystem", args: ["/workspace"] }
  },
  web_search: {
    name: "web_search",
    transport_type: "stdio",
    config: { command: "mcp-server-brave-search" }
  }
}

# Initialize all clients
manager = MCPClientManager.new
CLIENTS_CONFIG.each do |name, config|
  manager.add_client(name, **config)
end
```

### Context-Aware Client Usage

```ruby
class AIAssistant
  def initialize
    @mcp_manager = MCPClientManager.new
    setup_clients
  end
  
  def setup_clients
    @mcp_manager.add_client(:code, 
      name: "github",
      transport_type: "sse",
      config: { url: "https://github-mcp-server.example.com" }
    )
    
    @mcp_manager.add_client(:files,
      name: "filesystem",
      transport_type: "stdio",
      config: { command: "mcp-server-filesystem", args: [Dir.pwd] }
    )
  end
  
  def handle_code_request(prompt)
    client = @mcp_manager.get_client(:code)
    tools = client.tools
    # Use GitHub-specific tools for code-related tasks
    process_with_tools(prompt, tools)
  end
  
  def handle_file_request(prompt)
    client = @mcp_manager.get_client(:files)
    resources = client.resources
    # Use filesystem tools for file operations
    process_with_resources(prompt, resources)
  end
  
  private
  
  def process_with_tools(prompt, tools)
    # Implementation for using tools
  end
  
  def process_with_resources(prompt, resources)
    # Implementation for using resources
  end
end
```

### Dynamic Client Management

```ruby
class DynamicMCPManager
  def initialize
    @clients = {}
    @client_configs = {}
  end
  
  def register_client_type(name, config)
    @client_configs[name] = config
  end
  
  def get_or_create_client(name)
    return @clients[name] if @clients[name]&.alive?
    
    config = @client_configs[name]
    raise "Unknown client type: #{name}" unless config
    
    @clients[name] = RubyLLM::MCP.client(**config)
  end
  
  def health_check
    @clients.each do |name, client|
      unless client.alive?
        puts "Client #{name} is not responsive, recreating..."
        @clients[name] = RubyLLM::MCP.client(**@client_configs[name])
      end
    end
  end
end
```

## Best Practices

### 1. Proper Client Lifecycle Management

```ruby
# Always stop clients when done
begin
  client = RubyLLM::MCP.client(**config)
  # Use client...
ensure
  client&.stop
end
```

### 2. Error Handling and Resilience

```ruby
def safe_client_operation(client_name)
  client = @manager.get_client(client_name)
  yield client
rescue RubyLLM::MCP::Errors::ConnectionError => e
  puts "Client #{client_name} connection failed: #{e.message}"
  # Optionally recreate client
  @manager.remove_client(client_name)
  @manager.add_client(client_name, **@configs[client_name])
  retry
end
```

### 3. Resource Management

```ruby
class ResourceAwareMCPManager < MCPClientManager
  def initialize(max_clients: 10)
    super()
    @max_clients = max_clients
  end
  
  def add_client(name, **config)
    if @clients.size >= @max_clients
      # Remove least recently used client
      oldest_name = @clients.keys.first
      remove_client(oldest_name)
    end
    
    super(name, **config)
  end
end
```

## Integration with RubyLLM

### Using Multiple Clients in Chat

```ruby
# Set up clients for different capabilities
mcp_manager = MCPClientManager.new
mcp_manager.add_client(:github, name: "github", transport_type: "sse", config: {...})
mcp_manager.add_client(:filesystem, name: "filesystem", transport_type: "stdio", config: {...})

# Combine tools from multiple clients
all_tools = []
all_tools.concat(mcp_manager.get_client(:github).tools)
all_tools.concat(mcp_manager.get_client(:filesystem).tools)

# Use in RubyLLM chat
RubyLLM.chat(
  provider: :anthropic,
  model: "claude-3-5-sonnet-20241022",
  tools: all_tools,
  messages: [
    { role: "user", content: "List files in current directory and search GitHub for Ruby MCP examples" }
  ]
)
```

## Migration Guide

### From Single Client Usage

**Old Pattern:**
```ruby
# This would always return the same client
client = RubyLLM::MCP.client(name: "default", transport_type: "stdio")
tools = client.tools
```

**New Pattern:**
```ruby
# Explicitly manage client lifecycle
@default_client ||= RubyLLM::MCP.client(name: "default", transport_type: "stdio")
tools = @default_client.tools
```

### From Singleton to Multiple Clients

**Old Pattern:**
```ruby
# Single client for everything
client = RubyLLM::MCP.client(name: "filesystem", transport_type: "stdio")
# Limited to one server's capabilities
```

**New Pattern:**
```ruby
# Multiple specialized clients
manager = MCPClientManager.new
manager.add_client(:files, name: "filesystem", transport_type: "stdio", config: {...})
manager.add_client(:web, name: "web_search", transport_type: "sse", config: {...})
manager.add_client(:github, name: "github", transport_type: "sse", config: {...})

# Use appropriate client for each task
file_tools = manager.get_client(:files).tools
web_tools = manager.get_client(:web).tools
github_tools = manager.get_client(:github).tools
```

## Troubleshooting

### Common Issues

1. **Memory Leaks**: Always call `stop` on clients when done
2. **Connection Limits**: Monitor the number of active clients
3. **Resource Conflicts**: Ensure clients don't conflict with each other (e.g., file locks)
4. **Performance**: Too many concurrent clients can impact performance

### Debugging

```ruby
# Add logging to track client lifecycle
class DebugMCPManager < MCPClientManager
  def add_client(name, **config)
    puts "Creating client: #{name}"
    super
  end
  
  def remove_client(name)
    puts "Removing client: #{name}"
    super
  end
  
  def health_check
    @clients.each do |name, client|
      status = client.alive? ? "alive" : "dead"
      puts "Client #{name}: #{status}"
    end
  end
end
```

This enhanced client management capability enables building more sophisticated AI applications that can leverage multiple MCP servers simultaneously, each specialized for different types of tasks and data sources.