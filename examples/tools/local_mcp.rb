# frozen_string_literal: true

require "bundler/setup"
require "ruby_llm/mcp"
require "debug"
require "dotenv"

Dotenv.load

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
end

RubyLLM::MCP.support_complex_parameters!

# Test with filesystem MCP server using stdio transport
client = RubyLLM::MCP.client(
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "npx",
    args: [
      "@modelcontextprotocol/server-filesystem",
      File.expand_path("..", __dir__) # Allow access to the current directory
    ]
  }
)

puts "Transport type: #{File.expand_path('..', __dir__)}"

puts "Connected to filesystem MCP server"
puts "Available tools:"
tools = client.tools
puts tools.map { |tool| "  - #{tool.name}: #{tool.description}" }.join("\n")
puts "-" * 50

chat = RubyLLM.chat(model: "gpt-4.1")
chat.with_tools(*client.tools)

message = "Can you list the files in the current directory and tell me what's in the README file if it exists?"
puts "Asking: #{message}"
puts "-" * 50

chat.ask(message) do |chunk|
  if chunk.tool_call?
    chunk.tool_calls.each do |key, tool_call|
      next if tool_call.name.nil?

      puts "\n🔧 Tool call(#{key}) - #{tool_call.name}"
    end
  else
    print chunk.content
  end
end
puts "\n"
