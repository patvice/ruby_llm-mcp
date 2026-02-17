# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides guard method functionality to validate before execution
        module GuardChecks
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            # Register a guard method that must return true to proceed
            # @param method_name [Symbol] name of the guard method
            def guard(method_name)
              guards << method_name
            end

            # Store guard methods
            def guards
              @guards ||= []
            end

            # Inherit guards from parent classes
            def inherited(subclass)
              super
              subclass.instance_variable_set(:@guards, guards.dup)
            end
          end

          # Execute with guard checks
          def call
            # Run all guards first
            guard_result = execute_guards
            return guard_result unless guard_result.nil?

            super
          end

          protected

          # Check if all guards pass
          def guards_pass?
            self.class.guards.all? do |guard_method|
              result = send(guard_method)
              result == true || result.nil? # nil means no guard configured, allow it
            end
          end

          # Execute guards and return failure result if any fail
          def execute_guards
            self.class.guards.each do |guard_method|
              result = send(guard_method)
              unless result == true || result.nil?
                message = result.is_a?(String) ? result : "Guard #{guard_method} failed"
                return guard_failed(message)
              end
            end
            nil # All guards passed
          end

          # Override this in your handler to define what happens on guard failure
          # @param message [String] the failure message
          def guard_failed(message)
            raise "Guard check failed: #{message}"
          end
        end
      end
    end
  end
end
