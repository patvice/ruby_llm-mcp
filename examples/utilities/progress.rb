# frozen_string_literal: true

require "bundler/setup"
require "ruby_llm/mcp"
require "debug"
require "dotenv"

Dotenv.load

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
end

RubyLLM::MCP.configure do |config|
  config.support_complex_parameters!
  config.log_level = Logger::ERROR
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
client.on_progress do |progress|
  puts "Progress: #{progress.progress}%"
end

result = client.tool("progress").execute(operation: "processing", steps: 3)
puts "Result: #{result}"
