# frozen_string_literal: true

# Adapter Testing DSL
#
# This module provides helper methods to create flexible tests that can run
# across different MCP adapters (Native/RubyLLM and MCP SDK).
#
# Usage:
#   each_client do |config|
#     # runs on all 4 clients (stdio-native, streamable-native, stdio-mcp-sdk, streamable-mcp-sdk)
#   end
#
#   each_client(adapter: :native) do |config|
#     # runs only on native clients
#   end
#
#   each_client_supporting(:logging, :sampling) do |config|
#     # runs only where adapter supports both features
#   end
#
# Adding New Adapter-Specific Tests:
#
# 1. For basic features (tools, resources, prompts) - use `each_client`
#    These tests will run on all adapters including MCP SDK
#
# 2. For advanced features (logging, sampling, etc.) - use `each_client_supporting(:feature_name)`
#    These tests will only run on adapters that declare support for those features
#
# 3. To check which features an adapter supports, see:
#    - lib/ruby_llm/mcp/adapters/ruby_llm_adapter.rb - supports line
#    - lib/ruby_llm/mcp/adapters/mcp_sdk_adapter.rb - supports line
#
# 4. The DSL automatically skips MCP SDK clients if the 'mcp' gem is not installed
#
module AdapterTestHelpers
  # Iterate over clients, optionally filtered by adapter type
  #
  # @param adapter [Symbol] Filter by adapter type (:all, :native, :mcp_sdk, :ruby_llm)
  # @yield [config] Block to execute for each matching client configuration
  # @yieldparam config [Hash] Client configuration hash from CLIENT_OPTIONS
  def each_client(adapter: :all, &block)
    # Normalize adapter filter
    adapter_filter = normalize_adapter(adapter)

    filtered_configs = if adapter_filter == :all
                         CLIENT_OPTIONS
                       else
                         CLIENT_OPTIONS.select { |config| normalize_adapter(config[:adapter]) == adapter_filter }
                       end

    filtered_configs.each do |config|
      # Skip if this is an MCP SDK client and the gem is not available
      next if config[:adapter] == :mcp_sdk && !ClientRunner.mcp_sdk_available?

      context "with #{config[:name]}" do
        let(:client) { ClientRunner.fetch_client(config[:name]) }

        instance_exec(config, &block)
      end
    end
  end

  # Iterate over clients whose adapter supports ALL specified features
  #
  # @param features [Array<Symbol>] Features that must be supported
  # @yield [config] Block to execute for each matching client configuration
  # @yieldparam config [Hash] Client configuration hash from CLIENT_OPTIONS
  def each_client_supporting(*features, &block)
    filtered_configs = CLIENT_OPTIONS.select do |config|
      adapter_class = get_adapter_class(config[:adapter])
      features.all? { |feature| adapter_class.support?(feature) }
    end

    filtered_configs.each do |config|
      # Skip if this is an MCP SDK client and the gem is not available
      next if config[:adapter] == :mcp_sdk && !ClientRunner.mcp_sdk_available?

      context "with #{config[:name]}" do
        let(:client) { ClientRunner.fetch_client(config[:name]) }

        instance_exec(config, &block)
      end
    end
  end

  # Get all clients using a specific adapter type
  #
  # @param adapter [Symbol] Adapter type (:mcp_sdk, :ruby_llm)
  # @return [Array<Hash>] Filtered client configurations
  def clients_with_adapter(adapter)
    adapter_filter = normalize_adapter(adapter)
    CLIENT_OPTIONS.select { |config| normalize_adapter(config[:adapter]) == adapter_filter }
  end

  # Get all clients supporting specific features
  #
  # @param features [Array<Symbol>] Features that must be supported
  # @return [Array<Hash>] Filtered client configurations
  def clients_supporting(*features)
    CLIENT_OPTIONS.select do |config|
      adapter_class = get_adapter_class(config[:adapter])
      features.all? { |feature| adapter_class.support?(feature) }
    end
  end

  # Check if a specific client supports a feature
  #
  # @param config [Hash] Client configuration
  # @param feature [Symbol] Feature to check
  # @return [Boolean] Whether the client's adapter supports the feature
  def client_supports?(config, feature)
    adapter_class = get_adapter_class(config[:adapter])
    adapter_class.support?(feature)
  end

  private

  # Normalize adapter name to handle aliases
  def normalize_adapter(adapter)
    case adapter.to_sym
    when :native, :ruby_llm
      :ruby_llm
    when :mcp_sdk, :sdk
      :mcp_sdk
    when :all
      :all
    else
      adapter.to_sym
    end
  end

  # Get the adapter class for a given adapter type
  def get_adapter_class(adapter)
    case normalize_adapter(adapter)
    when :ruby_llm
      RubyLLM::MCP::Adapters::RubyLLMAdapter
    when :mcp_sdk
      RubyLLM::MCP::Adapters::MCPSdkAdapter
    else
      raise ArgumentError, "Unknown adapter type: #{adapter}"
    end
  end
end

# Make the helpers available to all RSpec examples
RSpec.configure do |config|
  config.extend AdapterTestHelpers
end
