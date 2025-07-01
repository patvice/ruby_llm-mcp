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

firecrawl_mcp = RubyLLM::MCP.client(
  name: "firecrawl-server",
  transport_type: :stdio,
  config: {
    command: "npx",
    args: ["-y", "firecrawl-mcp"],
    env: {
      "FIRECRAWL_API_KEY" => ENV.fetch("FIRECRAWL_API_KEY", nil)
    }
  }
)

chat = RubyLLM.chat(model: "gpt-4.1")
chat.with_tool(firecrawl_mcp.tool("firecrawl_scrape"))

message = "Can you scrape the website https://discord.com/blog and tell me what the purpose of this site is?"
message2 = "Can you return this in a markdown format?"

chat.ask([message, message2].join("\n")) do |chunk|
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
