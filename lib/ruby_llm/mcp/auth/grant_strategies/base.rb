# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      module GrantStrategies
        # Base strategy for OAuth grant types
        # Defines interface for grant-specific configuration
        class Base
          # Get token endpoint authentication method
          # @return [String] auth method (e.g., "none", "client_secret_post")
          def auth_method
            raise NotImplementedError, "#{self.class} must implement #auth_method"
          end

          # Get list of grant types to request during registration
          # @return [Array<String>] grant types
          def grant_types_list
            raise NotImplementedError, "#{self.class} must implement #grant_types_list"
          end

          # Get list of response types to request during registration
          # @return [Array<String>] response types
          def response_types_list
            raise NotImplementedError, "#{self.class} must implement #response_types_list"
          end
        end
      end
    end
  end
end
