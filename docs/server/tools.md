---
layout: default
title: Tools
parent: Server Interactions
nav_order: 1
description: "Working with MCP tools - discovery, execution, human-in-the-loop, and streaming"
---

# Tools
{: .no_toc }

MCP tools are server-side operations that can be executed by LLMs to perform actions like reading files, making API calls, or running calculations. This guide covers everything you need to know about working with MCP tools.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Tool Discovery

### Listing Available Tools

Get all tools from an MCP server:

```ruby
client = RubyLLM::MCP.client(
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "npx",
    args: ["@modelcontextprotocol/server-filesystem", "/path/to/directory"]
  }
)

# Get all available tools
tools = client.tools
puts "Available tools:"
tools.each do |tool|
  puts "- #{tool.name}: #{tool.description}"

  # Show input schema
  tool.input_schema["properties"]&.each do |param, schema|
    required = tool.input_schema["required"]&.include?(param) ? " (required)" : ""
    puts "  - #{param}: #{schema['description']}#{required}"
  end
end
```

### Getting a Specific Tool

```ruby
# Get a specific tool by name
file_tool = client.tool("read_file")
puts "Tool: #{file_tool.name}"
puts "Description: #{file_tool.description}"
puts "Input schema: #{file_tool.input_schema}"
```

### Refreshing Tool Cache

Tools are cached to improve performance. Refresh when needed:

```ruby
# Refresh all tools
tools = client.tools(refresh: true)

# Refresh a specific tool
tool = client.tool("read_file", refresh: true)
```

## Tool Execution

### Direct Tool Execution

Execute tools directly without using LLM:

```ruby
# Execute a file reading tool
result = client.execute_tool(
  name: "read_file",
  parameters: {
    path: "README.md"
  }
)

puts "File contents: #{result}"
```

### Structured Tool Output

{: .new }
Structured tool output is available in MCP Protocol 2025-06-18.

Tools can now specify output schemas for structured responses, enabling type-safe tool interactions:

```ruby
# Tools with output schemas will automatically validate their structured content
tool = client.tool("data_analyzer")
result = tool.execute(data: "sample data")

# If the tool has an output schema, structured content is validated
# Invalid structured outputs will return an error
puts result # Returns validated structured content or error message
```

#### Checking Tool Schemas

Tools now support both input and output schemas:

```ruby
tools = client.tools
tools.each do |tool|
  puts "Tool: #{tool.name}"

  # Input schema (parameters)
  if tool.input_schema
    puts "  Input Schema: #{tool.input_schema}"
  end

  # Output schema (return value validation)
  if tool.output_schema
    puts "  Output Schema: #{tool.output_schema}"
  end
end
```

#### Validation Behavior

- **Valid structured output**: Returns the structured content
- **Invalid structured output**: Returns an error with validation details
- **No output schema**: Behaves as before (text-based output)

#### Example with Schema Validation

```ruby
# A tool that returns structured data
weather_tool = client.tool("get_weather")
result = weather_tool.execute(location: "San Francisco")

# If the tool has an output schema, the result is validated
if result.is_a?(Hash) && result[:error]
  puts "Tool validation failed: #{result[:error]}"
else
  # Structured, validated output
  puts "Temperature: #{result.temperature}"
  puts "Humidity: #{result.humidity}"
end
```

#### Human-Friendly Display Names

{: .new }
Tools now support title fields for better user experience in MCP Protocol 2025-06-18:

```ruby
tools = client.tools
tools.each do |tool|
  # Access display-friendly title if available
  title = tool.annotations&.title || tool.name
  puts "Tool: #{title} - #{tool.description}"

  # Check if the tool has a human-friendly title
  if tool.annotations&.title
    puts "  Display Name: #{tool.annotations.title}"
    puts "  Programmatic Name: #{tool.name}"
  end
end
```

This separates programmatic identifiers from human-readable names for better UX.

### Using Tools with RubyLLM

Integrate tools into LLM conversations:

```ruby
# Add all tools to a chat
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*client.tools)

# Ask the LLM to use tools
response = chat.ask("Read the README.md file and summarize it")
puts response
```

### Individual Tool Usage

Use specific tools in conversations:

```ruby
# Get a specific tool
search_tool = client.tool("search_files")

# Add only this tool to the chat
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(search_tool)

response = chat.ask("Search for all Ruby files in the project")
puts response
```

## Human-in-the-Loop

Control tool execution with human approval:

### Basic Human-in-the-Loop

```ruby
# Set up human approval for all tools
client.on_human_in_the_loop do |name, params|
  puts "Tool: #{name}"
  puts "Parameters: #{params}"
  print "Allow execution? (y/n): "
  gets.chomp.downcase == 'y'
end

# Execute tool (will prompt for approval)
result = client.execute_tool(
  name: "delete_file",
  parameters: { path: "important.txt" }
)
```

### Conditional Human-in-the-Loop

```ruby
# Only require approval for dangerous operations
client.on_human_in_the_loop do |name, params|
  dangerous_tools = ["delete_file", "modify_file", "execute_command"]

  if dangerous_tools.include?(name)
    puts "⚠️  Dangerous operation requested!"
    puts "Tool: #{name}"
    puts "Parameters: #{params}"
    print "Allow execution? (y/n): "
    gets.chomp.downcase == 'y'
  else
    true  # Allow safe operations automatically
  end
end
```

### Programmatic Guards

Use logic to determine approval:

```ruby
client.on_human_in_the_loop do |name, params|
  case name
  when "delete_file"
    # Don't allow deletion of important files
    !params[:path].include?("important")
  when "api_call"
    # Only allow API calls to trusted domains
    params[:url].start_with?("https://api.trusted.com")
  else
    true
  end
end
```

### Handler Classes

{: .label .label-green }
1.0+

Handler classes provide a powerful, testable way to handle approvals with async support.

#### Basic Handler Class

```ruby
class SafeToolHandler < RubyLLM::MCP::Handlers::HumanInTheLoopHandler
  option :safe_tools, default: ["read_file", "list_files"]

  def execute
    if options[:safe_tools].include?(tool_name)
      approve
    else
      deny("Tool '#{tool_name}' requires explicit approval")
    end
  end
end

# Use globally
RubyLLM::MCP.configure do |config|
  config.on_human_in_the_loop SafeToolHandler
end

# Or per-client
client.on_human_in_the_loop(SafeToolHandler, safe_tools: ["read_file", "list_files"])
```

#### Handler with Guards

```ruby
class ParameterValidationHandler < RubyLLM::MCP::Handlers::HumanInTheLoopHandler
  guard :check_parameters
  guard :check_path_safety

  def execute
    # Logic here only runs if guards pass
    approve
  end

  private

  def check_parameters
    return true unless parameters[:path]
    return true unless parameters[:path].include?("..")

    "Path traversal detected"
  end

  def check_path_safety
    return true unless parameters[:path]
    return true unless parameters[:path].start_with?("/etc")

    "Access to system directories denied"
  end
end
```

#### Async Approval via Websocket

Perfect for requiring real user approval via UI:

```ruby
class WebsocketApprovalHandler < RubyLLM::MCP::Handlers::HumanInTheLoopHandler
  async_execution timeout: 300 # 5 minutes

  option :websocket_service, required: true
  option :user_id, required: true

  on_timeout do
    deny("User did not respond in time")
  end

  def execute
    # Send approval request to user's browser/app
    options[:websocket_service].broadcast(
      "approvals_#{options[:user_id]}",
      {
        type: "approval_request",
        id: approval_id,
        tool: tool_name,
        parameters: parameters
      }
    )

    # Return :pending - approval happens later via registry
    :pending
  end
end

# Configure handler
client.on_human_in_the_loop(
  WebsocketApprovalHandler,
  websocket_service: ActionCable.server,
  user_id: current_user.id
)

# When user approves/denies via websocket:
class ApprovalsChannel < ApplicationCable::Channel
  def approve(data)
    RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.approve(
      data["approval_id"]
    )
  end

  def deny(data)
    RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.deny(
      data["approval_id"],
      reason: data["reason"]
    )
  end
end
```

#### Built-in Auto-Approve Handler

```ruby
# Simple auto-approve handler included with the gem
client.on_human_in_the_loop(
  RubyLLM::MCP::Handlers::AutoApproveToolHandler,
  safe_tools: ["read_file", "list_files"],
  dangerous_tools: ["delete_file", "execute_command"]
)
```

#### Backward Compatibility

Handler classes are fully backward compatible:

```ruby
# Old way (still works)
client.on_human_in_the_loop do |name, params|
  name != "dangerous_tool"
end

# New way (preferred for complex logic)
client.on_human_in_the_loop(MyApprovalHandler)
```

## Streaming Responses

Monitor tool execution in real-time:

```ruby
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*client.tools)

chat.ask("Analyze all files in the project") do |chunk|
  if chunk.tool_call?
    chunk.tool_calls.each do |key, tool_call|
      puts "🔧 Using tool: #{tool_call.name}"
      puts "   Parameters: #{tool_call.parameters}"
    end
  else
    print chunk.content
  end
end
```

## Error Handling

### Tool Execution Errors

```ruby
begin
  result = client.execute_tool(
    name: "read_file",
    parameters: { path: "/nonexistent/file.txt" }
  )
rescue RubyLLM::MCP::Errors::ToolError => e
  puts "Tool execution failed: #{e.message}"
  puts "Error details: #{e.error_details}"
end
```

### Tool Not Found

```ruby
begin
  tool = client.tool("nonexistent_tool")
rescue RubyLLM::MCP::Errors::ToolNotFound => e
  puts "Tool not found: #{e.message}"
end
```

### Timeout Errors

```ruby
begin
  result = client.execute_tool(
    name: "slow_operation",
    parameters: { size: "large" }
  )
rescue RubyLLM::MCP::Errors::TimeoutError => e
  puts "Tool execution timed out: #{e.message}"
end
```

## Tool Inspection

### Understanding Tool Schema

```ruby
tool = client.tool("create_file")

# Basic information
puts "Name: #{tool.name}"
puts "Description: #{tool.description}"

# Input schema details
schema = tool.input_schema
puts "Required parameters: #{schema['required']}"

schema['properties'].each do |param, details|
  puts "Parameter: #{param}"
  puts "  Type: #{details['type']}"
  puts "  Description: #{details['description']}"
  puts "  Required: #{schema['required']&.include?(param)}"
end
```

### Tool Capabilities

```ruby
# Check if tool supports specific features
tool = client.tool("search_files")

# Check parameter types
if tool.input_schema["properties"]["pattern"]
  puts "Supports pattern matching"
end

if tool.input_schema["properties"]["recursive"]
  puts "Supports recursive search"
end
```

## Advanced Tool Usage

### Tool Result Processing

```ruby
# Process tool results
result = client.execute_tool(
  name: "list_files",
  parameters: { directory: "/path/to/search" }
)

# Parse JSON results
if result.is_a?(String) && result.start_with?("{")
  parsed = JSON.parse(result)
  puts "Found #{parsed['files'].length} files"
end
```

### Chaining Tool Calls

```ruby
# First tool call
files = client.execute_tool(
  name: "list_files",
  parameters: { directory: "/project" }
)

# Use result in second tool call
parsed_files = JSON.parse(files)
ruby_files = parsed_files["files"].select { |f| f.end_with?(".rb") }

ruby_files.each do |file|
  content = client.execute_tool(
    name: "read_file",
    parameters: { path: file }
  )
  puts "File: #{file}"
  puts content
end
```

### Tool Composition

```ruby
# Create a higher-level operation using multiple tools
def analyze_project(client)
  # Get project structure
  structure = client.execute_tool(
    name: "list_files",
    parameters: { directory: ".", recursive: true }
  )

  # Read important files
  readme = client.execute_tool(
    name: "read_file",
    parameters: { path: "README.md" }
  )

  # Search for specific patterns
  todos = client.execute_tool(
    name: "search_files",
    parameters: { pattern: "TODO", directory: "." }
  )

  {
    structure: structure,
    readme: readme,
    todos: todos
  }
end

# Use in a chat
analysis = analyze_project(client)
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*client.tools)

response = chat.ask("Based on this project analysis: #{analysis}, provide recommendations")
puts response
```

## Performance Considerations

### Tool Caching

```ruby
# Cache expensive tool results
class ToolCache
  def initialize(client)
    @client = client
    @cache = {}
  end

  def execute_tool(name, parameters)
    key = "#{name}:#{parameters.hash}"

    @cache[key] ||= @client.execute_tool(
      name: name,
      parameters: parameters
    )
  end
end

cached_client = ToolCache.new(client)
```

### Batch Operations

```ruby
# Process multiple files efficiently
files = ["file1.txt", "file2.txt", "file3.txt"]
contents = {}

files.each do |file|
  contents[file] = client.execute_tool(
    name: "read_file",
    parameters: { path: file }
  )
end

# Use all contents in a single chat
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*client.tools)

response = chat.ask("Analyze these files: #{contents}")
puts response
```

## Next Steps

- **[Resources]({% link server/resources.md %})** - Working with MCP resources
- **[Prompts]({% link server/prompts.md %})** - Using predefined prompts
- **[Notifications]({% link server/notifications.md %})** - Handling real-time updates
