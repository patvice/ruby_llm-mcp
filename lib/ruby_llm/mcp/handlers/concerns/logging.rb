# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides access to MCP logger
        module Logging
          protected

          # Access to logger
          def logger
            RubyLLM::MCP.logger
          end
        end
      end
    end
  end
end
