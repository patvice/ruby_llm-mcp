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

      def tasks?
        !@capabilities["tasks"].nil?
      end

      def tasks_list?
        !@capabilities.dig("tasks", "list").nil?
      end

      def tasks_cancel?
        !@capabilities.dig("tasks", "cancel").nil?
      end

      def task_augmented_tool_call?
        !@capabilities.dig("tasks", "requests", "tools", "call").nil?
      end
    end
  end
end
