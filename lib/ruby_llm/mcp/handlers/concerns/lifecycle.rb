# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides lifecycle hook management (before_execute, after_execute)
        # and orchestrates the execution flow
        module Lifecycle
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            # Register a before_execute hook
            # @param method_name [Symbol, nil] method name to call, or pass a block
            # @yield block to execute before main execution
            def before_execute(method_name = nil, &block)
              before_hooks << (method_name || block)
            end

            # Register an after_execute hook
            # @param method_name [Symbol, nil] method name to call, or pass a block
            # @yield block to execute after main execution, receives result as parameter
            def after_execute(method_name = nil, &block)
              after_hooks << (method_name || block)
            end

            # Store before hooks
            def before_hooks
              @before_hooks ||= []
            end

            # Store after hooks
            def after_hooks
              @after_hooks ||= []
            end

            # Inherit hooks from parent classes
            def inherited(subclass)
              super
              subclass.instance_variable_set(:@before_hooks, before_hooks.dup)
              subclass.instance_variable_set(:@after_hooks, after_hooks.dup)
            end
          end

          # Main entry point - orchestrates hooks and execution
          # @return [Object] result from execute method
          def call
            # Execute before hooks
            execute_hooks(self.class.before_hooks)

            # Execute main logic
            result = execute

            # Execute after hooks
            execute_hooks(self.class.after_hooks, result)

            result
          end

          # Abstract method - must be implemented by subclasses
          # @return [Object] handler-specific result
          def execute
            raise NotImplementedError, "#{self.class.name} must implement #execute"
          end

          private

          # Execute a list of hooks
          def execute_hooks(hooks, *args)
            hooks.each do |hook|
              if hook.is_a?(Symbol)
                send(hook, *args)
              else
                instance_exec(*args, &hook)
              end
            end
          end
        end
      end
    end
  end
end




