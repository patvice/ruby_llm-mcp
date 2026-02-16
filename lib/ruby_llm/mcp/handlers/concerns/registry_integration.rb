# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides integration with approval and elicitation registries
        module RegistryIntegration
          protected

          # Store approval context in registry
          # @param id [String] approval ID
          # @param context [Hash] approval context
          def store_in_approval_registry(id, context)
            HumanInTheLoopRegistry.store(id, context)
          end

          # Retrieve approval context from registry
          # @param id [String] approval ID
          # @return [Hash, nil] approval context or nil
          def retrieve_from_approval_registry(id)
            HumanInTheLoopRegistry.retrieve(id)
          end

          # Remove approval from registry
          # @param id [String] approval ID
          def remove_from_approval_registry(id)
            HumanInTheLoopRegistry.remove(id)
          end

          # Store elicitation in registry
          # @param id [String] elicitation ID
          # @param elicitation [RubyLLM::MCP::Elicitation] elicitation object
          def store_in_elicitation_registry(id, elicitation)
            ElicitationRegistry.store(id, elicitation)
          end

          # Retrieve elicitation from registry
          # @param id [String] elicitation ID
          # @return [RubyLLM::MCP::Elicitation, nil] elicitation or nil
          def retrieve_from_elicitation_registry(id)
            ElicitationRegistry.retrieve(id)
          end

          # Remove elicitation from registry
          # @param id [String] elicitation ID
          def remove_from_elicitation_registry(id)
            ElicitationRegistry.remove(id)
          end
        end
      end
    end
  end
end
