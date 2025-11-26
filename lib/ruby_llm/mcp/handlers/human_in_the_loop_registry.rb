# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Registry for tracking pending human-in-the-loop approvals
      # Provides thread-safe storage and retrieval for async completions
      class HumanInTheLoopRegistry
        class << self
          # Get the singleton registry instance
          def instance
            @instance ||= new
          end

          # Delegate class methods to instance
          def store(id, approval)
            instance.store(id, approval)
          end

          def retrieve(id)
            instance.retrieve(id)
          end

          def remove(id)
            instance.remove(id)
          end

          def approve(id)
            instance.approve(id)
          end

          def deny(id, reason: "Denied")
            instance.deny(id, reason: reason)
          end

          def clear
            instance.clear
          end

          def size
            instance.size
          end
        end

        # Stores approval context: { promise:, timeout:, tool_name:, parameters: }
        def initialize
          @registry = {}
          @timeouts = {}
          @registry_mutex = Mutex.new
          @timeouts_mutex = Mutex.new
        end

        # Store an approval in the registry
        # @param id [String] approval ID
        # @param approval_context [Hash] context with promise, timeout, etc.
        def store(id, approval_context)
          @registry_mutex.synchronize do
            @registry[id] = approval_context
          end

          # Set up timeout if specified
          if approval_context[:timeout]
            schedule_timeout(id, approval_context[:timeout])
          end

          RubyLLM::MCP.logger.debug("Stored approval #{id} in registry")
        end

        # Retrieve an approval from the registry
        # @param id [String] approval ID
        # @return [Hash, nil] approval context or nil if not found
        def retrieve(id)
          @registry_mutex.synchronize do
            @registry[id]
          end
        end

        # Remove an approval from the registry
        # @param id [String] approval ID
        # @return [Hash, nil] removed approval context or nil
        def remove(id)
          approval = nil

          # Cancel timeout first (before removing from registry)
          cancel_timeout(id)

          # Remove from registry
          approval = @registry_mutex.synchronize do
            @registry.delete(id)
          end

          RubyLLM::MCP.logger.debug("Removed approval #{id} from registry") if approval
          approval
        ensure
          # Ensure timeout thread is cleaned up even if removal fails
          cancel_timeout(id) unless approval
        end

        # Approve a pending request
        # @param id [String] approval ID
        def approve(id)
          approval = retrieve(id)

          if approval && approval[:promise]
            RubyLLM::MCP.logger.info("Approving #{id}")
            approval[:promise].resolve(true)
            remove(id)
          else
            RubyLLM::MCP.logger.warn("Attempted to approve unknown approval #{id}")
          end
        end

        # Deny a pending request
        # @param id [String] approval ID
        # @param reason [String] denial reason
        def deny(id, reason: "Denied")
          approval = retrieve(id)

          if approval && approval[:promise]
            RubyLLM::MCP.logger.info("Denying #{id}: #{reason}")
            approval[:promise].resolve(false)
            remove(id)
          else
            RubyLLM::MCP.logger.warn("Attempted to deny unknown approval #{id}")
          end
        end

        # Clear all pending approvals
        def clear
          ids = @registry_mutex.synchronize { @registry.keys }
          ids.each { |id| cancel_timeout(id) }
          @registry_mutex.synchronize { @registry.clear }
          RubyLLM::MCP.logger.debug("Cleared human-in-the-loop registry")
        end

        # Get number of pending approvals
        # @return [Integer] count of pending approvals
        def size
          @registry_mutex.synchronize { @registry.size }
        end

        private

        # Schedule timeout for an approval
        def schedule_timeout(id, timeout_seconds)
          timeout_thread = Thread.new do
            sleep timeout_seconds
            handle_timeout(id)
          end

          @timeouts_mutex.synchronize do
            @timeouts[id] = timeout_thread
          end
        end

        # Cancel scheduled timeout
        # Ensures thread is properly terminated and resources are freed
        def cancel_timeout(id)
          timeout_thread = @timeouts_mutex.synchronize do
            @timeouts.delete(id)
          end

          return unless timeout_thread

          # Safely terminate the thread
          begin
            timeout_thread.kill if timeout_thread.alive?
            timeout_thread.join(0.1) # Wait briefly for cleanup
          rescue StandardError => e
            RubyLLM::MCP.logger.debug("Error cancelling timeout thread for #{id}: #{e.message}")
          end
        end

        # Handle timeout event
        def handle_timeout(id)
          approval = retrieve(id)

          if approval && approval[:promise]
            RubyLLM::MCP.logger.warn("Approval #{id} timed out")
            approval[:promise].resolve(false)
            # Remove from registry without cancelling timeout (we're IN the timeout thread)
            remove_without_timeout_cancel(id)
          end
        end

        # Remove from registry without cancelling timeout thread
        # Used when called from within the timeout thread itself
        def remove_without_timeout_cancel(id)
          @registry_mutex.synchronize do
            @registry.delete(id)
          end

          # Clean up timeout thread reference
          @timeouts_mutex.synchronize do
            @timeouts.delete(id)
          end

          RubyLLM::MCP.logger.debug("Removed approval #{id} from registry")
        end
      end
    end
  end
end
