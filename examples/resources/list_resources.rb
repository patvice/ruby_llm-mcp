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
  name: "streamable_mcp",
  transport_type: :streamable,
  config: {
    url: "http://localhost:3005/mcp"
  }
)
resources = client.resources

resources.each do |resource|
  puts "Resource: #{resource.name}"
  puts "Description: #{resource.description}"
  puts "MIME Type: #{resource.mime_type}"
  puts "Template: #{resource.template?}"
  puts "Content: #{resource.content}"
  puts "--------------------------------"
end
