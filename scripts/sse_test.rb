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
  config.log_level = Logger::DEBUG
  config.support_complex_parameters!
end

mcp = RubyLLM::MCP.client(
  name: "test-server",
  transport_type: :sse,
  config: {
    url: "http://localhost:3006/mcp/sse"
  }
)

mcp.tools.each do |tool|
  puts "Tool: #{tool.name}"
  puts "Description: #{tool.description}"
  puts "Parameters: #{tool.parameters}"
  puts "---"
end
