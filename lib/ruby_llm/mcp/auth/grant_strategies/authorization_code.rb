# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      module GrantStrategies
        # Authorization Code grant strategy
        # Used for user authorization with PKCE (OAuth 2.1)
        class AuthorizationCode < Base
          # Public clients don't use client_secret
          # @return [String] "none"
          def auth_method
            "none"
          end

          # Authorization code and refresh token grants
          # @return [Array<String>] grant types
          def grant_types_list
            %w[authorization_code refresh_token]
          end

          # Only "code" response type for authorization code flow
          # @return [Array<String>] response types
          def response_types_list
            ["code"]
          end
        end
      end
    end
  end
end
