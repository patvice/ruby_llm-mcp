# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Base class for sampling request handlers
      # Provides access to sample object, guards, and helper methods
      #
      # @example Basic sampling handler
      #   class MySamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
      #     def execute
      #       response = default_chat_completion("gpt-4")
      #       accept(response)
      #     end
      #   end
      #
      # @example Sampling handler with guards
      #   class GuardedSamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
      #     allow_models "gpt-4", "claude-3-opus"
      #
      #     guard :check_model
      #     guard :check_token_limit
      #
      #     def execute
      #       response = default_chat_completion(sample.model)
      #       accept(response)
      #     end
      #
      #     private
      #
      #     def check_model
      #       return true if model_allowed?(sample.model)
      #       "Model not allowed"
      #     end
      #
      #     def check_token_limit
      #       return true if sample.max_tokens <= 4000
      #       "Too many tokens"
      #     end
      #   end
      class SamplingHandler
        include Concerns::Options
        include Concerns::Lifecycle
        include Concerns::Logging
        include Concerns::ErrorHandling
        include Concerns::GuardChecks
        include Concerns::ModelFiltering
        include Concerns::SamplingActions

        attr_reader :coordinator

        # Initialize sampling handler
        # @param sample [RubyLLM::MCP::Sample] the sampling request
        # @param coordinator [Object] the coordinator managing the request
        # @param options [Hash] handler-specific options
        def initialize(sample:, coordinator:, **options)
          @sample = sample
          @coordinator = coordinator
          super(**options)
        end
      end
    end
  end
end




