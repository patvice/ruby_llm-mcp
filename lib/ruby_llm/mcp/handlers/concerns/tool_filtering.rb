# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides tool filtering functionality (allow/deny lists)
        module ToolFiltering
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            # Declare allowed tools for this handler
            # @param tools [Array<String>] list of allowed tool names
            def allow_tools(*tools)
              option :allowed_tools, default: tools.flatten
            end

            # Declare denied tools for this handler
            # @param tools [Array<String>] list of denied tool names
            def deny_tools(*tools)
              option :denied_tools, default: tools.flatten
            end
          end

          attr_reader :tool_name

          protected

          # Check if the current tool is allowed
          def tool_allowed?
            allowed = options[:allowed_tools] || []
            return true if allowed.empty?

            allowed.include?(tool_name)
          end

          # Check if the current tool is denied
          def tool_denied?
            denied = options[:denied_tools] || []
            return false if denied.empty?

            denied.include?(tool_name)
          end
        end
      end
    end
  end
end
