# frozen_string_literal: true

class McpOauthCredential < ApplicationRecord
  belongs_to :user

  encrypts :token_data
  encrypts :client_info_data

  validates :server_url, presence: true, uniqueness: { scope: :user_id }

  # Get token object from stored data
  def token
    return nil unless token_data.present?

    RubyLLM::MCP::Auth::Token.from_h(JSON.parse(token_data, symbolize_names: true))
  end

  # Set token and update expiration
  def token=(token_obj)
    self.token_data = token_obj.to_h.to_json
    self.token_expires_at = token_obj.expires_at
  end

  # Get client info object from stored data
  def client_info
    return nil unless client_info_data.present?

    RubyLLM::MCP::Auth::ClientInfo.from_h(JSON.parse(client_info_data, symbolize_names: true))
  end

  # Set client info
  def client_info=(info_obj)
    self.client_info_data = info_obj.to_h.to_json
  end

  # Check if token is expired
  def expired?
    token&.expired?
  end

  # Check if token expires soon (within 5 minutes)
  def expires_soon?
    token&.expires_soon?
  end

  # Check if token is valid
  def valid_token?
    token && !token.expired?
  end
end
