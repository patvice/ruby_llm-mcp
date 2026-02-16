<div align="center">
  <img src="/docs/assets/images/rubyllm-mcp-logo-text.svg" alt="RubyLLM::MCP" height="120" width="250">

  <strong>MCP made simple for RubyLLM.</strong>

  <p>
    <a href="https://badge.fury.io/rb/ruby_llm-mcp"><img src="https://badge.fury.io/rb/ruby_llm-mcp.svg" alt="Gem Version" /></a>
    <a href="https://rubygems.org/gems/ruby_llm-mcp"><img alt="Gem Downloads" src="https://img.shields.io/gem/dt/ruby_llm-mcp"></a>
  </p>
</div>

`ruby_llm-mcp` connects Ruby applications to [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) servers and integrates them directly with [RubyLLM](https://github.com/crmne/ruby_llm).

## Simple Configuration

```ruby
require 'ruby_llm/mcp'

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
end

RubyLLM::MCP.configure do |config|
  config.request_timeout = 8_000
  config.protocol_version = '2025-11-25'
end

client = RubyLLM::MCP.client(
  name: 'filesystem',
  transport_type: :stdio,
  config: {
    command: 'npx',
    args: ['@modelcontextprotocol/server-filesystem', Dir.pwd]
  }
)
```

## Core Use Cases

### Tools

```ruby
chat = RubyLLM.chat(model: 'gpt-4o-mini')
chat.with_tools(*client.tools)

puts chat.ask('List the Ruby files in this project and summarize what you find.')
```

### Resources

```ruby
resource = client.resource('project_readme')

chat = RubyLLM.chat(model: 'gpt-4o-mini')
chat.with_resource(resource)

puts chat.ask('Summarize this project in 5 bullets.')
```

### Prompts

```ruby
prompt = client.prompt('code_review')
chat = RubyLLM.chat(model: 'gpt-4o-mini')

response = chat.ask_prompt(prompt, arguments: {
  language: 'ruby',
  focus: 'security'
})

puts response
```

## Support At A Glance

- **Native MCP client implementation (`:ruby_llm`)** with full protocol support through `2025-11-25`
- **Official MCP SDK adapter support (`:mcp_sdk`)** via the `mcp` gem for teams that prefer SDK-backed integration
- **OAuth implementation** for authenticated streamable HTTP MCP servers
- **Transports:** `stdio`, `sse`, `streamable` / `streamable_http`
- **Core server features:** tools, resources, resource templates, prompts, notifications
- **Advanced client features:** sampling, roots, progress tracking, human-in-the-loop, elicitation
- **Task lifecycle APIs** (`tasks/list`, `tasks/get`, `tasks/result`, `tasks/cancel`) are experimental

> [!WARNING]
> MCP task support is experimental and subject to change in both the MCP spec and this gem's implementation.

## Install

Add to your Gemfile:

```ruby
gem 'ruby_llm-mcp'
```

Optional (for `:mcp_sdk` adapter):

```ruby
gem 'mcp', '~> 0.4'
```

Then run:

```bash
bundle install
```

## Setup

1. Set your RubyLLM provider credentials (for example `OPENAI_API_KEY`).
2. Start or access an MCP server.
3. Create a `RubyLLM::MCP.client` and attach its tools/resources/prompts to chat flows.

Full docs: [rubyllm-mcp.com](https://rubyllm-mcp.com)

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/patvice/ruby_llm-mcp).

## License

Released under the MIT License.
