# frozen_string_literal: true

module RubyLLM
  module MCP
    class Capabilities
      attr_reader :capabilities

      def initialize(capabilities)
        @capabilities = capabilities
      end

      def resources_list_changed?
        @capabilities.dig("resources", "listChanged") || false
      end

      def resource_subscribe?
        @capabilities.dig("resources", "subscribe") || false
      end

      def tools_list_changed?
        @capabilities.dig("tools", "listChanged") || false
      end
    end
  end
end
