---
layout: default
title: Roots
parent: Client Interactions
nav_order: 8
description: "MCP roots - provide filesystem access to servers for enhanced capabilities"
---

# Roots
{: .no_toc }

MCP roots provide filesystem access to MCP servers, allowing them to understand your project structure and access files within specified directories. This enables more powerful and context-aware server operations.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Roots functionality allows MCP servers to:

- Access files and directories within configured root paths
- Understand project structure and organization
- Provide more accurate file-based operations
- Support relative path resolution

{: .warning }
Only provide root access to trusted MCP servers, as this grants filesystem access to the specified directories.

## Basic Configuration

### Configuring Roots

```ruby
RubyLLM::MCP.configure do |config|
  config.roots = [
    "/path/to/project",
    Rails.root,
    Pathname.new("/another/project")
  ]
end

# Create client with roots configured
client = RubyLLM::MCP.client(
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "bunx",
    args: ["@modelcontextprotocol/server-filesystem"]
  }
)
```

### Accessing Roots Information

```ruby
# Get configured root paths
puts "Root paths:"
client.roots.paths.each do |path|
  puts "- #{path}"
end

# Check if a path is within roots
puts client.roots.includes?("/path/to/project/file.txt") # true
puts client.roots.includes?("/outside/path/file.txt")    # false
```

## Dynamic Root Management

### Adding Roots at Runtime

```ruby
# Add a new root directory
client.roots.add("/new/project/path")

# Add multiple roots
client.roots.add("/project1", "/project2")

# Verify addition
puts "Updated roots:"
client.roots.paths.each { |path| puts "- #{path}" }
```

### Removing Roots

```ruby
# Remove a specific root
client.roots.remove("/path/to/remove")

# Remove multiple roots
client.roots.remove("/project1", "/project2")

# Clear all roots
client.roots.clear
```

### Root Validation

```ruby
# Validate that roots exist before adding
def add_validated_root(client, path)
  if File.directory?(path)
    client.roots.add(path)
    puts "Added root: #{path}"
  else
    puts "Warning: Directory does not exist: #{path}"
  end
end

add_validated_root(client, "/existing/path")
add_validated_root(client, "/nonexistent/path")
```

## Next Steps

- **[Rails Integration]({% link guides/rails-integration.md %})** - Complete Rails integration guide
- Back to **[Configuration]({% link configuration.md %})** for more client setup options
