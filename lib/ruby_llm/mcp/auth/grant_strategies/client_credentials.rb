# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      module GrantStrategies
        # Client Credentials grant strategy
        # Used for application authentication without user interaction
        class ClientCredentials < Base
          # Client credentials require client_secret
          # @return [String] "client_secret_post"
          def auth_method
            "client_secret_post"
          end

          # Client credentials and refresh token grants
          # @return [Array<String>] grant types
          def grant_types_list
            %w[client_credentials refresh_token]
          end

          # No response types for client credentials flow (no redirect)
          # @return [Array<String>] response types (empty)
          def response_types_list
            []
          end
        end
      end
    end
  end
end
