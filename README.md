<img src="/docs/assets/images/rubyllm-mcp-logo-text.svg" alt="RubyLLM" height="120" width="250">

**Aiming to make using MCPs with RubyLLM and Ruby as easy as possible.**

This project is a Ruby client for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/), designed to work seamlessly with [RubyLLM](https://github.com/crmne/ruby_llm). This gem enables Ruby applications to connect to MCP servers and use their tools, resources and prompts as part of LLM conversations.

For a more detailed guide, see the [RubyLLM::MCP docs](https://rubyllm-mcp.com/).

Stable MCP support is enabled by default (`2025-06-18`), with opt-in draft protocol track support (`2026-01-26`).

<div class="badge-container">
  <a href="https://badge.fury.io/rb/ruby_llm-mcp"><img src="https://badge.fury.io/rb/ruby_llm-mcp.svg" alt="Gem Version" /></a>
  <a href="https://rubygems.org/gems/ruby_llm-mcp"><img alt="Gem Downloads" src="https://img.shields.io/gem/dt/ruby_llm-mcp"></a>
</div>

## RubyLLM::MCP Features

- 🎛️ **Dual SDK Support** _(v0.8+)_: Choose between native full-featured implementation or official MCP SDK
- 🔌 **Multiple Transport Types**: Streamable HTTP, STDIO, and SSE transports
- 🛠️ **Tool Integration**: Automatically converts MCP tools into RubyLLM-compatible tools
- 📄 **Resource Management**: Access and include MCP resources (files, data) and resource templates in conversations
- 🎯 **Prompt Integration**: Use predefined MCP prompts with arguments for consistent interactions
- 🎨 **Client Features**: Support for sampling, roots, progress tracking, human-in-the-loop, and elicitation
- 🧪 **Protocol Track Control**: Stable-by-default with opt-in draft protocol behavior
- 🧩 **Extensions & MCP Apps**: Global + per-client extension configuration with canonical MCP UI/MCP Apps extension support
- 🔧 **Enhanced Chat Interface**: Extended RubyLLM chat methods for seamless MCP integration
- 🔄 **Multiple Client Management**: Create and manage multiple MCP clients simultaneously for different servers and purposes
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

## Choosing an Adapter

Starting with version 0.8.0, RubyLLM MCP supports multiple SDK adapters:

### RubyLLM Adapter (Default)

The native implementation with full MCP protocol support:

```ruby
client = RubyLLM::MCP.client(
  name: "server",
  adapter: :ruby_llm,  # Default, can be omitted
  transport_type: :stdio,
  config: { command: "mcp-server" }
)
```

**Features**: All MCP features including SSE transport, sampling, roots, progress tracking, etc.

### MCP SDK Adapter

The official Anthropic-maintained SDK:

```ruby
# Add to Gemfile
gem 'mcp', '~> 0.4'

# Use in code
client = RubyLLM::MCP.client(
  name: "server",
  adapter: :mcp_sdk,
  transport_type: :stdio,
  config: { command: "mcp-server" }
)
```

**Features**: Core MCP features (tools, resources, prompts). No SSE, sampling, or advanced features.

See the [Adapters Guide](https://rubyllm-mcp.com/guides/adapters.html) for detailed comparison.

## Draft Protocol Track

RubyLLM MCP defaults to the stable track:

```ruby
RubyLLM::MCP.configure do |config|
  config.protocol_track = :stable  # default
end
```

Enable draft behavior globally:

```ruby
RubyLLM::MCP.configure do |config|
  config.protocol_track = :draft
end
```

Protocol version precedence is:
1. Per-client `config[:protocol_version]`
2. Global `config.protocol_version` (explicit override)
3. `config.protocol_track` derived default

## Extensions & MCP Apps

RubyLLM MCP supports extension negotiation so clients can advertise optional capabilities (including MCP Apps / UI capabilities).

Register extensions globally:

```ruby
RubyLLM::MCP.configure do |config|
  config.extensions.enable_apps(
    "mimeTypes" => ["text/html;profile=mcp-app"]
  )
end
```

Override per client:

```ruby
client = RubyLLM::MCP.client(
  name: "server",
  adapter: :ruby_llm,
  transport_type: :streamable,
  config: {
    url: "https://example.com/mcp",
    protocol_version: "2026-01-26",
    extensions: {
      "io.modelcontextprotocol/ui" => {}
    }
  }
)
```

Extension behavior:
- Outbound extension advertisement uses canonical ID `io.modelcontextprotocol/ui`
- Inbound capability parsing accepts alias `io.modelcontextprotocol/apps`
- `enable_apps` is a convenience helper for MCP Apps/UI extension registration
- `:ruby_llm` adapter provides full extension negotiation
- `:mcp_sdk` adapter accepts the same config surface in passive mode and warns once per process

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

### Manual Tool Execution

You can also execute MCP tools directly:

```ruby
# Tools Execution
tool = client.tool("search_files")

# Execute a specific tool
result = tool.execute(
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

## Development

After checking out the repo, run `bundle` to install dependencies. Then, run `bundle exec rake` to run the tests. Tests currently use `bun` to run test MCP servers You can also run `bin/console` for an interactive prompt that will allow you to experiment.

There are also examples you you can run to verify the gem is working as expected.

```bash
bundle exec ruby examples/tools/local_mcp.rb
```

Rails + TypeScript MCP app example:

```bash
cd examples/mcp_app
./bin/setup
./bin/reset-data
cd rails_app
bin/rails server
```

## Contributing

We welcome contributions! Bug reports and pull requests are welcome on GitHub at https://github.com/patvice/ruby_llm-mcp.

## License

Released under the MIT License.
