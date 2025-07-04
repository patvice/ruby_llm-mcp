# frozen_string_literal: true

require "bundler/setup"
require "ruby_llm/mcp"
require "debug"
require "dotenv"

Dotenv.load

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
end

# Test with streamable HTTP transport
client = RubyLLM::MCP.client(
  name: "streamable_mcp",
  transport_type: :streamable,
  config: {
    url: "http://localhost:3005/mcp"
  }
)

puts "Connected to streamable MCP server"
puts "Available tools:"
tools = client.tools
puts tools.map { |tool| "  - #{tool.name}: #{tool.description}" }.join("\n")
puts "-" * 50

chat = RubyLLM.chat(model: "gpt-4.1")
chat.with_tools(*client.tools)

message = "Can you use one of the available tools to help me with a task? can you add 1 and 3 and output the result?"
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
