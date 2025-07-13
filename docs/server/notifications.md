---
layout: default
title: Notifications
parent: Server Interactions
nav_order: 4
description: "Handling MCP notifications - logging, progress updates, and resource changes"
---

# Notifications

MCP notifications provide real-time updates from servers about ongoing operations, resource changes, and system events. This guide covers how to handle different types of notifications in your application.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Types of Notifications

### Logging Notifications

Logging notifications allow MCP servers to send real-time log messages during tool execution.

### Progress Notifications

Progress notifications provide updates about the progress of long-running operations.

### Resource Update Notifications

Resource update notifications inform you when resources on the server have changed.

## Logging Notifications

### Basic Logging Setup

```ruby
client = RubyLLM::MCP.client(
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "bunx",
    args: ["@modelcontextprotocol/server-filesystem", "/path/to/directory"]
  }
)

# Set up logging notification handler
client.on_logging do |logging|
  puts "#{logging.level.upcase}: #{logging.message}"
end

# Execute a tool that produces logging
tool = client.tool("long_running_operation")
result = tool.execute(operation: "data_processing")

# Output might look like:
# INFO: Starting data processing
# INFO: Processing file 1 of 100
# WARNING: File corrupted, skipping
# INFO: Processing complete
```

### Logging Levels

Handle different logging levels:

```ruby
# Handle all logging levels
client.on_logging do |logging|
  case logging.level
  when RubyLLM::MCP::Logging::DEBUG
    puts "🐛 DEBUG: #{logging.message}"
  when RubyLLM::MCP::Logging::INFO
    puts "ℹ️  INFO: #{logging.message}"
  when RubyLLM::MCP::Logging::WARNING
    puts "⚠️  WARNING: #{logging.message}"
  when RubyLLM::MCP::Logging::ERROR
    puts "❌ ERROR: #{logging.message}"
  when RubyLLM::MCP::Logging::FATAL
    puts "💀 FATAL: #{logging.message}"
  end
end
```

### Filtering Logging by Level

```ruby
# Only handle warning and error messages
client.on_logging(RubyLLM::MCP::Logging::WARNING) do |logging|
  puts "⚠️  #{logging.level.upcase}: #{logging.message}"
end

# Only handle errors
client.on_logging(RubyLLM::MCP::Logging::ERROR) do |logging|
  puts "❌ ERROR: #{logging.message}"
  # Log to file, send alert, etc.
end
```

### Structured Logging

```ruby
# Create structured log entries
client.on_logging do |logging|
  log_entry = {
    timestamp: Time.now.iso8601,
    level: logging.level,
    message: logging.message,
    source: "mcp_server"
  }

  # Send to your logging system
  Rails.logger.info(log_entry.to_json)
end
```

## Progress Notifications

### Basic Progress Tracking

```ruby
# Set up progress notification handler
client.on_progress do |progress|
  puts "Progress: #{progress.progress}% - #{progress.message}"
end

# Execute a tool that supports progress notifications
tool = client.tool("large_file_processor")
result = tool.execute(file_path: "/path/to/large/file.csv")

# Output might look like:
# Progress: 25% - Processing data...
# Progress: 50% - Validating records...
# Progress: 75% - Generating report...
# Progress: 100% - Complete
```

### Progress with UI Updates

```ruby
# Update a progress bar or UI element
client.on_progress do |progress|
  # Update progress bar
  update_progress_bar(progress.progress)

  # Update status message
  update_status_message(progress.message)

  # Log progress
  Rails.logger.info("Progress: #{progress.progress}% - #{progress.message}")
end

def update_progress_bar(percentage)
  # Update your UI progress bar
  bar_width = (percentage / 100.0 * 50).to_i
  bar = "#" * bar_width + "-" * (50 - bar_width)
  print "\r[#{bar}] #{percentage}%"
end

def update_status_message(message)
  # Update status display
  puts "\nStatus: #{message}"
end
```

### Progress with Timeouts

```ruby
# Track progress with timeout handling
class ProgressTracker
  def initialize(client)
    @client = client
    @last_progress = 0
    @last_update = Time.now
  end

  def setup_tracking(timeout: 300)
    @client.on_progress do |progress|
      @last_progress = progress.progress
      @last_update = Time.now

      puts "Progress: #{progress.progress}% - #{progress.message}"

      # Check if we're stuck
      if stalled?
        puts "⚠️  Progress appears stalled"
      end
    end
  end

  private

  def stalled?
    Time.now - @last_update > 60 # No progress for 60 seconds
  end
end

tracker = ProgressTracker.new(client)
tracker.setup_tracking(timeout: 300)
```

## Resource Update Notifications

### Basic Resource Updates

```ruby
# Handle resource update notifications
client.on_resource_updated do |resource_uri|
  puts "Resource updated: #{resource_uri}"

  # Refresh the resource in your cache
  refresh_resource_cache(resource_uri)
end

# Execute operations that might update resources
tool = client.tool("modify_file")
result = tool.execute(path: "config.json", content: new_config)

# Output: Resource updated: file:///path/to/config.json
```

### Automatic Resource Refresh

```ruby
# Automatically refresh resources when they change
class ResourceManager
  def initialize(client)
    @client = client
    @cache = {}
    setup_update_handler
  end

  def resource(name)
    @cache[name] ||= @client.resource(name)
  end

  private

  def setup_update_handler
    @client.on_resource_updated do |resource_uri|
      # Find and refresh the cached resource
      @cache.each do |name, cached_resource|
        if cached_resource.uri == resource_uri
          puts "Refreshing cached resource: #{name}"
          @cache[name] = @client.resource(name, refresh: true)
          break
        end
      end
    end
  end
end

manager = ResourceManager.new(client)
resource = manager.resource("config_file")
```

### Resource Change Notifications

```ruby
# Handle different types of resource changes
client.on_resource_updated do |resource_uri|
  case resource_uri
  when /\.json$/
    puts "JSON configuration updated: #{resource_uri}"
    reload_configuration
  when /\.log$/
    puts "Log file updated: #{resource_uri}"
    # Don't need to refresh log files usually
  else
    puts "Unknown resource updated: #{resource_uri}"
    # Generic refresh
    refresh_resource_cache(resource_uri)
  end
end
```

## Next Steps

- **[Sampling]({% link client/sampling.md %})** - Allow servers to use your LLM
- **[Roots]({% link client/roots.md %})** - Provide filesystem access to servers
- **[Rails Integration]({% link guides/rails-integration.md %})** - Complete Rails integration guide
