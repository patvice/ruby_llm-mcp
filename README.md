# RubyLLM::MCP

Aiming to make using MCPs with RubyLLM as easy as possible.

This project is a Ruby client for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/), designed to work seamlessly with [RubyLLM](https://github.com/crmne/ruby_llm). This gem enables Ruby applications to connect to MCP servers and use their tools, resources and prompts as part of LLM conversations.

**Note:** This project is still under development and the API is subject to change.

## Features

- 🔌 **Multiple Transport Types**: Streamable HTTP, and STDIO and legacy SSE transports
- 🛠️ **Tool Integration**: Automatically converts MCP tools into RubyLLM-compatible tools
- 📄 **Resource Management**: Access and include MCP resources (files, data) and resource templates in conversations
- 🎯 **Prompt Integration**: Use predefined MCP prompts with arguments for consistent interactions
- 🎛️ **Client Features**: Support for sampling and roots
- 🎨 **Enhanced Chat Interface**: Extended RubyLLM chat methods for seamless MCP integration
- 📚 **Simple API**: Easy-to-use interface that integrates seamlessly with RubyLLM

## Installation

```bash
bundle add ruby_llm-mcp
```

or add this line to your application's Gemfile:

```ruby
gem 'ruby_llm-mcp'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install ruby_llm-mcp
```

## Usage

### Basic Setup

First, configure your RubyLLM client and create an MCP connection:

```ruby
require 'ruby_llm/mcp'

# Configure RubyLLM
RubyLLM.configure do |config|
  config.openai_api_key = "your-api-key"
end

# Connect to an MCP server via SSE
client = RubyLLM::MCP.client(
  name: "my-mcp-server",
  transport_type: :sse,
  config: {
    url: "http://localhost:9292/mcp/sse"
  }
)

# Or connect via stdio
client = RubyLLM::MCP.client(
  name: "my-mcp-server",
  transport_type: :stdio,
  config: {
    command: "node",
    args: ["path/to/mcp-server.js"],
    env: { "NODE_ENV" => "production" }
  }
)

# Or connect via streamable HTTP
client = RubyLLM::MCP.client(
  name: "my-mcp-server",
  transport_type: :streamable,
  config: {
    url: "http://localhost:8080/mcp",
    headers: { "Authorization" => "Bearer your-token" }
  }
)
```

### Using MCP Tools with RubyLLM

```ruby
# Get available tools from the MCP server
tools = client.tools
puts "Available tools:"
tools.each do |tool|
  puts "- #{tool.name}: #{tool.description}"
end

# Create a chat session with MCP tools
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*client.tools)

# Ask a question that will use the MCP tools
response = chat.ask("Can you help me search for recent files in my project?")
puts response
```

### Human in the Loop

You can use the `on_human_in_the_loop` callback to allow the human to intervene in the tool call. This is useful for tools that require human input or programic input to verify if the tool should be executed.

For tool calls that have access to do important operations, there SHOULD always be a human in the loop with the ability to deny tool invocations.

```ruby
client.on_human_in_the_loop do |name, params|
  name == "add" && params[:a] == 1 && params[:b] == 2
end

tool = client.tool("add")
result = tool.execute(a: 1, b: 2)
puts result # 3

# If the human in the loop returns false, the tool call will be cancelled
result = tool.execute(a: 2, b: 2)
puts result # Tool execution error: Tool call was cancelled by the client

tool = client.tool("add")
result = tool.execute(a: 1, b: 2)
puts result
```

### Support Complex Parameters

If you want to support complex parameters, like an array of objects it currently requires a patch to RubyLLM itself. This is planned to be temporary until the RubyLLM is updated.

```ruby
RubyLLM::MCP.support_complex_parameters!
```

### Streaming Responses with Tool Calls

```ruby
chat = RubyLLM.chat(model: "gpt-4")
chat.with_tools(*client.tools)

chat.ask("Analyze my project structure") do |chunk|
  if chunk.tool_call?
    chunk.tool_calls.each do |key, tool_call|
      puts "\n🔧 Using tool: #{tool_call.name}"
    end
  else
    print chunk.content
  end
end
```

### Manual Tool Execution

You can also execute MCP tools directly:

```ruby
# Execute a specific tool
result = client.execute_tool(
  name: "search_files",
  parameters: {
    query: "*.rb",
    directory: "/path/to/search"
  }
)

puts result
```

### Working with Resources

MCP servers can provide access to resources - structured data that can be included in conversations. Resources come in two types: normal resources and resource templates.

#### Normal Resources

```ruby
# Get available resources from the MCP server
resources = client.resources
puts "Available resources:"
resources.each do |resource|
  puts "- #{resource.name}: #{resource.description}"
end

# Access a specific resource by name
file_resource = client.resource("project_readme")
content = file_resource.content
puts "Resource content: #{content}"

# Include a resource in a chat conversation for reference with an LLM
chat = RubyLLM.chat(model: "gpt-4")
chat.with_resource(file_resource)

# Or add a resource directly to the conversation
file_resource.include(chat)

response = chat.ask("Can you summarize this README file?")
puts response
```

#### Resource Templates

Resource templates are parameterized resources that can be dynamically configured:

```ruby
# Get available resource templates
templates = client.resource_templates
log_template = client.resource_template("application_logs")

# Use a template with parameters
chat = RubyLLM.chat(model: "gpt-4")
chat.with_resource_template(log_template, arguments: {
  date: "2024-01-15",
  level: "error"
})

response = chat.ask("What errors occurred on this date?")
puts response

# You can also get templated content directly
content = log_template.to_content(arguments: {
  date: "2024-01-15",
  level: "error"
})
puts content
```

### Working with Prompts

MCP servers can provide predefined prompts that can be used in conversations:

```ruby
# Get available prompts from the MCP server
prompts = client.prompts
puts "Available prompts:"
prompts.each do |prompt|
  puts "- #{prompt.name}: #{prompt.description}"
  prompt.arguments.each do |arg|
    puts "  - #{arg.name}: #{arg.description} (required: #{arg.required})"
  end
end

# Use a prompt in a conversation
greeting_prompt = client.prompt("daily_greeting")
chat = RubyLLM.chat(model: "gpt-4")

# Method 1: Ask prompt directly
response = chat.ask_prompt(greeting_prompt, arguments: { name: "Alice", time: "morning" })
puts response

# Method 2: Add prompt to chat and then ask
chat.with_prompt(greeting_prompt, arguments: { name: "Alice", time: "morning" })
response = chat.ask("Continue with the greeting")
```

### Combining Resources, Prompts, and Tools

You can combine all MCP features for powerful conversations:

```ruby
client = RubyLLM::MCP.client(
  name: "development-assistant",
  transport_type: :sse,
  config: { url: "http://localhost:9292/mcp/sse" }
)

chat = RubyLLM.chat(model: "gpt-4")

# Add tools for capabilities
chat.with_tools(*client.tools)

# Add resources for context
chat.with_resource(client.resource("project_structure"))
chat.with_resource(
  client.resource_template("recent_commits"),
  arguments: { days: 7 }
)

# Add prompts for guidance
chat.with_prompt(
  client.prompt("code_review_checklist"),
  arguments: { focus: "security" }
)

# Now ask for analysis
response = chat.ask("Please review the recent commits using the checklist and suggest improvements")
puts response
```

### Argument Completion

Some MCP servers support argument completion for prompts and resource templates:

```ruby
# For prompts
prompt = client.prompt("user_search")
suggestions = prompt.complete("username", "jo")
puts "Suggestions: #{suggestions.values}" # ["john", "joanna", "joseph"]

# For resource templates
template = client.resource_template("user_logs")
suggestions = template.complete("user_id", "123")
puts "Total matches: #{suggestions.total}"
puts "Has more results: #{suggestions.has_more}"
```

### Pagination

MCP servers can support pagination for their lists. The client will automatically paginate the lists to include all items from the list you wanted to pull.

Pagination is supported for tools, resources, prompts, and resource templates.

### Additional Chat Methods

The gem extends RubyLLM's chat interface with convenient methods for MCP integration:

```ruby
chat = RubyLLM.chat(model: "gpt-4")

# Add a single resource
chat.with_resource(resource)

# Add multiple resources
chat.with_resources(resource1, resource2, resource3)

# Add a resource template with arguments
chat.with_resource_template(resource_template, arguments: { key: "value" })

# Add a prompt with arguments
chat.with_prompt(prompt, arguments: { name: "Alice" })

# Ask using a prompt directly
response = chat.ask_prompt(prompt, arguments: { name: "Alice" })
```

## Rails Integration

RubyLLM MCP provides seamless Rails integration through a Railtie and generator system.

### Setup

Generate the configuration files:

```bash
rails generate ruby_llm:mcp:install
```

This creates:

- `config/initializers/ruby_llm_mcp.rb` - Main configuration
- `config/mcps.yml` - MCP servers configuration

### MCP Server Configuration

Configure your MCP servers in `config/mcps.yml`:

```yaml
mcp_servers:
  filesystem:
    transport_type: stdio
    command: npx
    args:
      - "@modelcontextprotocol/server-filesystem"
      - "<%= Rails.root %>"
    env: {}
    with_prefix: true

  api_server:
    transport_type: sse
    url: "https://api.example.com/mcp/sse"
    headers:
      Authorization: "Bearer <%= ENV['API_TOKEN'] %>"
```

### Automatic Client Management

With `launch_control: :automatic`, Rails will:

- Start all configured MCP clients when the application initializes
- Gracefully shut down clients when the application exits
- Handle client lifecycle automatically

However, it's very command to due to the performace of LLM calls that are made in the background.

For this, we recommend using `launch_control: :manual` and use `establish_connection` method to manage the client lifecycle manually inside your background jobs. It will provide you active connections to the MCP servers, and take care of closing them when the job is done.

```ruby
RubyLLM::MCP.establish_connection do |clients|
  chat = RubyLLM.chat(model: "gpt-4")
  chat.with_tools(*clients.tools)

  response = chat.ask("Hello, world!")
  puts response
end
```

You can also avoid this completely manually start and stop the clients if you so choose.

## Client Lifecycle Management

You can manage the MCP client connection lifecycle:

```ruby
client = RubyLLM::MCP.client(name: "my-server", transport_type: :stdio, start: false, config: {...})

# Manually start the connection
client.start

# Check if connection is alive
puts client.alive?

# Restart the connection
client.restart!

# Stop the connection
client.stop
```

### Ping

You can ping the MCP server to check if it is alive:

```ruby
client.ping # => true or false
```

## Refreshing Cached Data

The client caches tools, resources, prompts, and resource templates list calls are cached to reduce round trips back to the MCP server. You can refresh this cache:

```ruby
# Refresh all cached tools
tools = client.tools(refresh: true)

# Refresh a specific tool
tool = client.tool("search_files", refresh: true)

# Same pattern works for resources, prompts, and resource templates
resources = client.resources(refresh: true)
prompts = client.prompts(refresh: true)
templates = client.resource_templates(refresh: true)

# Or refresh specific items
resource = client.resource("project_readme", refresh: true)
prompt = client.prompt("daily_greeting", refresh: true)
template = client.resource_template("user_logs", refresh: true)
```

## Notifications

MCPs can produce notifications that happen in an async nature outside normal calls to the MCP server.

### Subscribing to a Resource Update

By default, the client will look for any resource cha to resource updates and refresh the resource content when it changes.

### Logging Notifications

MCPs can produce logging notifications for long-running tool operations. Logging notifications allow tools to send real-time updates about their execution status.

```ruby
client.on_logging do |logging|
  puts "Logging: #{logging.level} - #{logging.message}"
end

# Execute a tool that supports logging notifications
tool = client.tool("long_running_operation")
result = tool.execute(operation: "data_processing")

# Logging: info - Processing data...
# Logging: info - Processing data...
# Logging: warning - Something went wrong but not major...
```

Different levels of logging are supported:

```ruby
client.on_logging(RubyLLM::MCP::Logging::WARNING) do |logging|
  puts "Logging: #{logging.level} - #{logging.message}"
end

# Execute a tool that supports logging notifications
tool = client.tool("long_running_operation")
result = tool.execute(operation: "data_processing")

# Logging: warning - Something went wrong but not major...
```

### Progress Notifications

MCPs can produce progress notifications for long-running tool operations. Progress notifications allow tools to send real-time updates about their execution status.

**Note:** that we only support progress notifications for tool calls today.

```ruby
# Set up progress tracking
client.on_progress do |progress|
  puts "Progress: #{progress.progress}% - #{progress.message}"
end

# Execute a tool that supports progress notifications
tool = client.tool("long_running_operation")
result = tool.execute(operation: "data_processing")

# Progress 25% - Processing data...
# Progress 50% - Processing data...
# Progress 75% - Processing data...
# Progress 100% - Processing data...
puts result

# Result: { status: "success", data: "Processed data" }
```

## Client Features

The RubyLLM::MCP client provides support functionality that can be exposed to MCP servers. These features must be explicitly configured before creating client objects to ensure you're opting into this functionality.

### Roots

Roots provide MCP servers with access to underlying file system information. The implementation starts with a lightweight approach due to the MCP specification's current limitations on root usage.

When roots are configured, the client will:

- Expose roots as a supported capability to MCP servers
- Support dynamic addition and removal of roots during the client lifecycle
- Fire `notifications/roots/list_changed` events when roots are modified

#### Configuration

```ruby
RubyLLM::MCP.config do |config|
  config.roots = ["to/a/path", Rails.root]
end

client = RubyLLM::MCP::Client.new(...)
```

#### Usage

```ruby
# Access current root paths
client.roots.paths
# => ["to/a/path", #<Pathname:/to/rails/root/path>]

# Add a new root (fires list_changed notification)
client.roots.add("new/path")
client.roots.paths
# => ["to/a/path", #<Pathname:/to/rails/root/path>, "new/path"]

# Remove a root (fires list_changed notification)
client.roots.remove("to/a/path")
client.roots.paths
# => [#<Pathname:/to/rails/root/path>, "new/path"]
```

### Sampling

Sampling allows MCP servers to offload LLM requests to the MCP client rather than making them directly from the server. This enables MCP servers to optionally use LLM connections through the client.

#### Configuration

```ruby
RubyLLM::MCP.configure do |config|
  config.sampling.enabled = true
  config.sampling.preferred_model = "gpt-4.1"

  # Optional: Use a block for dynamic model selection
  config.sampling.preferred_model do |model_preferences|
    model_preferences.hints.first
  end

  # Optional: Add guards to filter sampling requests
  config.sampling.guard do |sample|
    sample.message.include("Hello")
  end
end
```

#### How It Works

With the above configuration:

- Clients will respond to all incoming sample requests using the specified model (`gpt-4.1`)
- Sample messages will only be approved if they contain the word "Hello" (when using the guard)
- The `preferred_model` can be a string or a proc that provides dynamic model selection based on MCP server characteristics

The `preferred_model` proc receives model preferences from the MCP server, allowing you to make intelligent model selection decisions based on the server's requirements for success.

## Transport Types

### SSE (Server-Sent Events)

Best for web-based MCP servers or when you need HTTP-based communication:

```ruby
client = RubyLLM::MCP.client(
  name: "web-mcp-server",
  transport_type: :sse,
  config: {
    url: "https://your-mcp-server.com/mcp/sse",
    headers: { "Authorization" => "Bearer your-token" }
  }
)
```

### Streamable HTTP

Best for HTTP-based MCP servers that support streaming responses:

```ruby
client = RubyLLM::MCP.client(
  name: "streaming-mcp-server",
  transport_type: :streamable,
  config: {
    url: "https://your-mcp-server.com/mcp",
    headers: { "Authorization" => "Bearer your-token" }
  }
)
```

### Stdio

Best for local MCP servers or command-line tools:

```ruby
client = RubyLLM::MCP.client(
  name: "local-mcp-server",
  transport_type: :stdio,
  config: {
    command: "python",
    args: ["-m", "my_mcp_server"],
    env: { "DEBUG" => "1" }
  }
)
```

## Creating Custom Transports

Part of the MCP specification outlines that custom transports can be used for some MCP servers. Out of the box, RubyLLM::MCP supports Streamable HTTP transports, STDIO and the legacy SSE transport.

You can create custom transport implementations to support additional communication protocols or specialized connection methods.

### Transport Registration

Register your custom transport with the transport factory:

```ruby
# Define your custom transport class
class MyCustomTransport
  # Implementation details...
end

# Register it with the factory
RubyLLM::MCP::Transport.register_transport(:my_custom, MyCustomTransport)

# Now you can use it
client = RubyLLM::MCP.client(
  name: "custom-server",
  transport_type: :my_custom,
  config: {
    # Your custom configuration
  }
)
```

### Required Interface

All transport implementations must implement the following interface:

```ruby
class MyCustomTransport
  # Initialize the transport
  def initialize(coordinator:, **config)
    @coordinator = coordinator # Uses for communication between the client and the MCP server
    @config = config # Transport-specific configuration
  end

  # Send a request and optionally wait for response
  # Returns a RubyLLM::MCP::Result object
  # body: the request body
  # add_id: true will add an id to the request
  # wait_for_response: true will wait for a response from the MCP server
  # Returns a RubyLLM::MCP::Result object
  def request(body, add_id: true, wait_for_response: true)
    # Implementation: send request and return result
    data = some_method_to_send_request_and_get_result(body)
    # Use Result object to make working with the protocol easier
    result = RubyLLM::MCP::Result.new(data)

    # Call the coordinator to process the result
    @coordinator.process_result(result)
    return if result.nil? # Some results are related to notifications and should not be returned to the client, but processed by the coordinator instead

    # Return the result
    result
  end

  # Check if transport is alive/connected
  def alive?
    # Implementation: return true if connected
  end

  # Start the transport connection
  def start
    # Implementation: establish connection
  end

  # Close the transport connection
  def close
    # Implementation: cleanup and close connection
  end

  # Set the MCP protocol version, used in some transports to identify the agreed upon protocol version
  def set_protocol_version(version)
    @protocol_version = version
  end
end
```

### The Result Object

The `RubyLLM::MCP::Result` class wraps MCP responses and provides convenient methods:

```ruby
result = transport.request(body)

# Core properties
result.id          # Request ID
result.method      # Request method
result.result      # Result data (hash)
result.params      # Request parameters
result.error       # Error data (hash)
result.session_id  # Session ID (if applicable)

# Type checking
result.success?      # Has result data
result.error?        # Has error data
result.notification? # Is a notification
result.request?      # Is a request
result.response?     # Is a response

# Specialized methods
result.tool_success?     # Successful tool execution
result.execution_error?  # Tool execution failed
result.matching_id?(id)  # Matches request ID
result.next_cursor?      # Has pagination cursor

# Error handling
result.raise_error!  # Raise exception if error
result.to_error      # Convert to Error object

# Notifications
result.notification  # Get notification object
```

### Error Handling

Custom transports should handle errors appropriately. If request fails, you should raise a `RubyLLM::MCP::Errors::TransportError` exception. If the request times out, you should raise a `RubyLLM::MCP::Errors::TimeoutError` exception. This will ensure that a cancellation notification is sent to the MCP server correctly.

```ruby
def request(body, add_id: true, wait_for_response: true)
  begin
    # Send request
    send_request(body)
  rescue SomeConnectionError => e
    # Convert to MCP transport error
    raise RubyLLM::MCP::Errors::TransportError.new(
      message: "Connection failed: #{e.message}",
      error: e
    )
  rescue Timeout::Error => e
    # Convert to MCP timeout error
    raise RubyLLM::MCP::Errors::TimeoutError.new(
      message: "Request timeout after #{@request_timeout}ms",
      request_id: body["id"]
    )
  end
end
```

## RubyLLM::MCP and Client Configuration Options

MCP comes with some common configuration options that can be set on the client.

```ruby
RubyLLM::MCP.configure do |config|
  # Set the progress handler
  config.support_complex_parameters!

  # Set parameters on the built in logger
  config.log_file = $stdout
  config.log_level = Logger::ERROR

  # Or add a custom logger
  config.logger = Logger.new(STDOUT)
end
```

### MCP Client Options

MCP client options are set on the client itself.

- `name`: A unique identifier for your MCP client
- `transport_type`: Either `:sse`, `:streamable`, or `:stdio`
- `start`: Whether to automatically start the connection (default: true)
- `request_timeout`: Timeout for requests in milliseconds (default: 8000)
- `config`: Transport-specific configuration
  - For SSE: `{ url: "http://...", headers: {...} }`
  - For Streamable: `{ url: "http://...", headers: {...} }`
  - For stdio: `{ command: "...", args: [...], env: {...} }`

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. Run `bundle exec rake` to test specs and run linters. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Examples

Check out the `examples/` directory for more detailed usage examples:

- `examples/tools/local_mcp.rb` - Complete example with stdio transport
- `examples/tools/sse_mcp_with_gpt.rb` - Example using SSE transport with GPT
- `examples/resources/list_resources.rb` - Example of listing and using resources
- `examples/prompts/streamable_prompt_call.rb` - Example of using prompts with streamable transport

## Contributing

We welcome contributions! Bug reports and pull requests are welcome on GitHub at https://github.com/patvice/ruby_llm-mcp.

## License

Released under the MIT License.
