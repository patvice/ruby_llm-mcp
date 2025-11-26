# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Detect if a handler is a class (vs a block/proc/lambda)
      # @param handler [Object] the handler to check
      # @return [Boolean] true if handler is a class
      def self.handler_class?(handler)
        handler.is_a?(Class) || (handler.respond_to?(:new) && !handler.respond_to?(:call))
      end
    end
  end
end
