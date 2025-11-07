# frozen_string_literal: true

class McpOauthState < ApplicationRecord
  belongs_to :user

  encrypts :pkce_data

  validates :state_param, presence: true
  validates :expires_at, presence: true

  scope :expired, -> { where("expires_at < ?", Time.current) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }

  # Clean up expired OAuth flow states
  def self.cleanup_expired
    expired.delete_all
  end

  # Get PKCE object from stored data
  def pkce
    return nil unless pkce_data.present?

    RubyLLM::MCP::Auth::PKCE.from_h(JSON.parse(pkce_data, symbolize_names: true))
  end

  # Set PKCE object
  def pkce=(pkce_obj)
    self.pkce_data = pkce_obj.to_h.to_json
  end
end
