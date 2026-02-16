# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides timeout handling for async operations
        module Timeouts
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            # Register timeout handler
            # @param method_name [Symbol, nil] method name or block
            def on_timeout(method_name = nil, &block)
              @timeout_handler = method_name || block
            end

            # Get timeout handler
            attr_reader :timeout_handler

            # Inherit timeout settings from parent classes
            def inherited(subclass)
              super
              subclass.instance_variable_set(:@timeout_handler, @timeout_handler)
            end
          end

          # Handle timeout event
          def handle_timeout
            handler = self.class.timeout_handler
            return default_timeout_action unless handler

            if handler.is_a?(Symbol)
              send(handler)
            else
              instance_exec(&handler)
            end
          end

          protected

          # Default action when timeout occurs (override in your handler)
          def default_timeout_action
            raise "Operation timed out"
          end
        end
      end
    end
  end
end
