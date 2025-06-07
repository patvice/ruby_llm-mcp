# frozen_string_literal: true

require "bundler/setup"
require "ruby_llm/mcp"
require "debug"
require "dotenv"

Dotenv.load

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
end

client = RubyLLM::MCP.client(
  name: "local_mcp",
  transport_type: :sse,
  config: {
    url: "http://localhost:9292/mcp/sse"
  }
)

tools = client.tools
puts "Tools:\n"
puts tools.map { |tool| "  #{tool.name}: #{tool.description}" }.join("\n")
puts "\nTotal tools: #{tools.size}"
