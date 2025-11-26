# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Registry for tracking pending elicitations
      # Provides thread-safe storage and retrieval for async completions
      class ElicitationRegistry
        class << self
          # Get the singleton registry instance
          def instance
            @instance ||= new
          end

          # Delegate class methods to instance
          def store(id, elicitation)
            instance.store(id, elicitation)
          end

          def retrieve(id)
            instance.retrieve(id)
          end

          def remove(id)
            instance.remove(id)
          end

          def complete(id, response:)
            instance.complete(id, response: response)
          end

          def cancel(id, reason: "Cancelled")
            instance.cancel(id, reason: reason)
          end

          def clear
            instance.clear
          end

          def size
            instance.size
          end
        end

        def initialize
          @registry = {}
          @timeouts = {}
          @registry_mutex = Mutex.new
          @timeouts_mutex = Mutex.new
        end

        # Store an elicitation in the registry
        # @param id [String] elicitation ID
        # @param elicitation [RubyLLM::MCP::Elicitation] elicitation object
        def store(id, elicitation)
          @registry_mutex.synchronize do
            @registry[id] = elicitation
          end

          # Set up timeout if specified
          if elicitation.timeout
            schedule_timeout(id, elicitation.timeout)
          end

          RubyLLM::MCP.logger.debug("Stored elicitation #{id} in registry")
        end

        # Retrieve an elicitation from the registry
        # @param id [String] elicitation ID
        # @return [RubyLLM::MCP::Elicitation, nil] elicitation or nil if not found
        def retrieve(id)
          @registry_mutex.synchronize do
            @registry[id]
          end
        end

        # Remove an elicitation from the registry
        # @param id [String] elicitation ID
        # @return [RubyLLM::MCP::Elicitation, nil] removed elicitation or nil
        def remove(id)
          elicitation = nil

          # Cancel timeout first (before removing from registry)
          cancel_timeout(id)

          # Remove from registry
          elicitation = @registry_mutex.synchronize do
            @registry.delete(id)
          end

          RubyLLM::MCP.logger.debug("Removed elicitation #{id} from registry") if elicitation
          elicitation
        ensure
          # Ensure timeout thread is cleaned up even if removal fails
          cancel_timeout(id) unless elicitation
        end

        # Complete a pending elicitation
        # @param id [String] elicitation ID
        # @param response [Hash] response data
        def complete(id, response:)
          elicitation = retrieve(id)

          if elicitation
            RubyLLM::MCP.logger.info("Completing elicitation #{id}")
            elicitation.complete(response)
            remove(id)
          else
            RubyLLM::MCP.logger.warn("Attempted to complete unknown elicitation #{id}")
          end
        end

        # Cancel a pending elicitation
        # @param id [String] elicitation ID
        # @param reason [String] cancellation reason
        def cancel(id, reason: "Cancelled")
          elicitation = retrieve(id)

          if elicitation
            RubyLLM::MCP.logger.info("Cancelling elicitation #{id}: #{reason}")
            elicitation.cancel_async(reason)
            remove(id)
          else
            RubyLLM::MCP.logger.warn("Attempted to cancel unknown elicitation #{id}")
          end
        end

        # Clear all pending elicitations
        def clear
          ids = @registry_mutex.synchronize { @registry.keys }
          ids.each { |id| cancel_timeout(id) }
          @registry_mutex.synchronize { @registry.clear }
          RubyLLM::MCP.logger.debug("Cleared elicitation registry")
        end

        # Get number of pending elicitations
        # @return [Integer] count of pending elicitations
        def size
          @registry_mutex.synchronize { @registry.size }
        end

        private

        # Schedule timeout for an elicitation
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
          elicitation = retrieve(id)

          if elicitation
            RubyLLM::MCP.logger.warn("Elicitation #{id} timed out")
            elicitation.timeout!
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

          RubyLLM::MCP.logger.debug("Removed elicitation #{id} from registry")
        end
      end
    end
  end
end
