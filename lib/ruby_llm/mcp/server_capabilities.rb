# frozen_string_literal: true

module RubyLLM
  module MCP
    class ServerCapabilities
      attr_accessor :capabilities

      def initialize(capabilities = {})
        @capabilities = capabilities
      end

      def resources_list?
        !@capabilities["resources"].nil?
      end

      def resources_list_changes?
        @capabilities.dig("resources", "listChanged") || false
      end

      def resource_subscribe?
        @capabilities.dig("resources", "subscribe") || false
      end

      def tools_list?
        !@capabilities["tools"].nil?
      end

      def tools_list_changes?
        @capabilities.dig("tools", "listChanged") || false
      end

      def prompt_list?
        !@capabilities["prompts"].nil?
      end

      def prompt_list_changes?
        @capabilities.dig("prompts", "listChanged") || false
      end

      def completion?
        !@capabilities["completions"].nil?
      end

      def logging?
        !@capabilities["logging"].nil?
      end

      def extensions
        value = @capabilities["extensions"]
        value.is_a?(Hash) ? value : {}
      end

      def extension?(id)
        !extension_capability(id).nil?
      end

      def extension_capability(id)
        canonical_id = Extensions::Registry.canonicalize_id(id)
        return nil if canonical_id.nil?

        normalized_extensions[canonical_id]
      end

      private

      def normalized_extensions
        extensions.each_with_object({}) do |(id, value), acc|
          canonical_id = Extensions::Registry.canonicalize_id(id) || id
          acc[canonical_id] = value
        end
      end
    end
  end
end
