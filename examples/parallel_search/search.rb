# frozen_string_literal: true

require "bundler/setup"
require "ruby_llm/mcp"
require "securerandom"

operation = ARGV.shift
input = ARGV.join(" ")
abort 'Usage: bundle exec ruby search.rb search "query" | fetch "https://example.com"' unless
  %w[search fetch].include?(operation) && !input.empty?

client = RubyLLM::MCP.client(
  name: "parallel_search",
  transport_type: :streamable,
  config: {
    url: "https://search.parallel.ai/mcp",
    headers: { "User-Agent" => "RubyLLM-MCP/#{RubyLLM::MCP::VERSION} parallel-search-example" }
  }
)

begin
  # One session per invocation; no Parallel or model API key is needed.
  session_id = SecureRandom.uuid
  tools = client.tools
  tool_name = operation == "search" ? "web_search" : "web_fetch"
  tool = tools.find { |available| available.name == tool_name }
  abort "Server did not expose #{tool_name}" unless tool

  arguments = if operation == "search"
                { objective: input, search_queries: [input], session_id: session_id }
              else
                { urls: [input], session_id: session_id }
              end
  result = tool.execute(**arguments)
  abort result[:error] if result.is_a?(Hash) && result[:error]

  puts result.text
ensure
  client.stop
end
