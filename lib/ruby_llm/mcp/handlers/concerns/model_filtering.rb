# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides model filtering functionality for sampling handlers
        module ModelFiltering
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            # Declare allowed models for this handler
            # @param models [Array<String>] list of allowed model names
            def allow_models(*models)
              option :allowed_models, default: models.flatten
            end
          end

          protected

          # Check if a model is allowed
          # @param model [String] the model name
          # @return [Boolean] true if allowed
          def model_allowed?(model)
            allowed = options[:allowed_models] || []
            return true if allowed.empty?

            allowed.include?(model)
          end
        end
      end
    end
  end
end
