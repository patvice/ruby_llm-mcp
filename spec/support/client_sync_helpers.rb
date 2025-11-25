# frozen_string_literal: true

# Client Synchronization Helpers
#
# This module provides helper methods for waiting on client state changes
# and tool availability in tests.
module ClientSyncHelpers
  # Wait for a specific tool to become available on a client
  #
  # @param client [RubyLLM::MCP::Client] The MCP client to check
  # @param tool_name [String] The name of the tool to wait for
  # @param max_wait_time [Integer, Float] Maximum time to wait in seconds (default: 5)
  # @return [RubyLLM::MCP::Tool] The tool instance when found
  # @raise [RuntimeError] If the tool is not found within the timeout period
  def wait_for_tool(client, tool_name, max_wait_time: 5)
    start_time = Time.now
    tool = nil

    loop do
      tool = client.tool(tool_name)
      break if tool

      elapsed = Time.now - start_time
      if elapsed > max_wait_time
        available_tools = begin
          client.tools.map(&:name).join(", ")
        rescue StandardError
          "Unable to fetch tools"
        end
        raise "Timeout waiting for tool '#{tool_name}' after #{elapsed.round(2)}s. \
               Available tools: #{available_tools}. Client alive: #{client.alive?}"
      end

      sleep 0.1
    end

    tool
  end
end

RSpec.configure do |config|
  config.include ClientSyncHelpers
end
