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
  config.log_level = Logger::ERROR
  config.support_complex_parameters!
end

mcp = RubyLLM::MCP.client(
  name: "test-server",
  transport_type: :sse,
  config: {
    url: "https://remote-mcp-server-authless.patrickgvice.workers.dev/sse"
  }
)

mcp.tools.each do |tool|
  puts "Tool: #{tool.name}"
  puts "Description: #{tool.description}"
  puts "Parameters: #{tool.parameters.map { |name, param| "#{name} (#{param.inspect})" }.join(', ')}"
  puts "---"
end
