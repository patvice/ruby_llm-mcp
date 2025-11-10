#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating Custom Storage for OAuth tokens
# Shows how to implement your own storage backend (database, Redis, file, etc.)
# This example uses an enhanced in-memory storage with persistence simulation
# Usage: ruby examples/oauth/custom_storage.rb

require "bundler/setup"
require "ruby_llm/mcp"
require "json"

# Configure MCP logging (optional)
RubyLLM::MCP.configure do |config|
  config.log_level = Logger::INFO
end

# Custom storage implementation
# In a real application, this could store to:
# - Database (PostgreSQL, MySQL, SQLite)
# - Redis for session storage
# - Encrypted file storage
# - Cloud KMS (AWS Secrets Manager, Google Secret Manager)
class CustomOAuthStorage
  def initialize
    @tokens = {}
    @client_infos = {}
    @server_metadata = {}
    @pkce_data = {}
    @state_data = {}

    puts "CustomOAuthStorage initialized"
    puts "Storage backends can be:"
    puts "  - Database (ActiveRecord, Sequel)"
    puts "  - Redis (for distributed systems)"
    puts "  - Encrypted files"
    puts "  - Cloud secret managers"
  end

  # Token storage methods
  def get_token(server_url)
    token = @tokens[server_url]
    puts "📖 Retrieved token for #{server_url}: #{token ? 'found' : 'not found'}"
    token
  end

  def set_token(server_url, token)
    puts "💾 Storing token for #{server_url}"
    @tokens[server_url] = token

    # In a real implementation, you might:
    # - Encrypt the token before storage
    # - Store in database with user association
    # - Set expiration in Redis
    # - Write to encrypted file
    simulate_persistence("token", server_url, token.to_h)
  end

  # Client registration storage
  def get_client_info(server_url)
    @client_infos[server_url]
  end

  def set_client_info(server_url, client_info)
    puts "💾 Storing client info for #{server_url}"
    @client_infos[server_url] = client_info
    simulate_persistence("client_info", server_url, client_info.to_h)
  end

  # Server metadata caching
  def get_server_metadata(server_url)
    @server_metadata[server_url]
  end

  def set_server_metadata(server_url, metadata)
    @server_metadata[server_url] = metadata
  end

  # PKCE state management (temporary)
  def get_pkce(server_url)
    @pkce_data[server_url]
  end

  def set_pkce(server_url, pkce)
    @pkce_data[server_url] = pkce
  end

  def delete_pkce(server_url)
    @pkce_data.delete(server_url)
  end

  # State parameter management (temporary)
  def get_state(server_url)
    @state_data[server_url]
  end

  def set_state(server_url, state)
    @state_data[server_url] = state
  end

  def delete_state(server_url)
    @state_data.delete(server_url)
  end

  # Custom method: list all stored tokens
  def list_tokens
    @tokens.keys
  end

  # Custom method: clear expired tokens
  def clear_expired_tokens
    expired = @tokens.select { |_, token| token.expired? }
    expired.each_key { |url| @tokens.delete(url) }
    puts "🧹 Cleared #{expired.size} expired tokens"
  end

  private

  # Simulate persistence to demonstrate storage patterns
  def simulate_persistence(type, key, data)
    # In a real app, this might be:

    # Database example:
    # OAuthToken.create!(
    #   server_url: key,
    #   access_token: encrypt(data[:access_token]),
    #   refresh_token: encrypt(data[:refresh_token]),
    #   expires_at: data[:expires_at]
    # )

    # Redis example:
    # redis.setex(
    #   "oauth:#{key}",
    #   data[:expires_in],
    #   JSON.generate(data)
    # )

    # File example:
    # File.write(
    #   "storage/oauth_#{Digest::SHA256.hexdigest(key)}.json",
    #   JSON.generate(data)
    # )

    puts "  └─ Would persist to storage: #{type} (#{data.keys.join(', ')})"
  end
end

# Example usage
puts "Custom Storage Example"
puts "=" * 60

# Create custom storage instance
storage = CustomOAuthStorage.new

puts "\n" + "=" * 60
puts "Using Custom Storage with Browser OAuth"
puts "-" * 60

# Example OAuth configuration
SERVER_URL = "https://accounts.google.com"
SCOPES = "openid profile email"

# Create BrowserOAuthProvider with custom storage
browser_oauth = RubyLLM::MCP::Auth::BrowserOAuthProvider.new(
  server_url: SERVER_URL,
  callback_port: 8080,
  scope: SCOPES,
  storage: storage  # Pass custom storage
)

puts "\nBrowser OAuth created with custom storage"
puts "All token operations will use CustomOAuthStorage"

# Simulate token storage (in a real app, this comes from OAuth flow)
puts "\n" + "-" * 60
puts "Simulating Token Storage Operations"
puts "-" * 60

# Create a mock token
mock_token = RubyLLM::MCP::Auth::Token.new(
  access_token: "mock_access_token_#{SecureRandom.hex(16)}",
  token_type: "Bearer",
  expires_in: 3600,
  scope: SCOPES,
  refresh_token: "mock_refresh_token_#{SecureRandom.hex(16)}"
)

# Store the token
puts "\nStoring mock token..."
storage.set_token(SERVER_URL, mock_token)

# Retrieve the token
puts "\nRetrieving token..."
retrieved_token = storage.get_token(SERVER_URL)
puts "✓ Token retrieved successfully" if retrieved_token

# List all tokens
puts "\nStored tokens:"
storage.list_tokens.each { |url| puts "  - #{url}" }

puts "\n" + "=" * 60
puts "Using Custom Storage with Standard OAuth"
puts "-" * 60

# You can also use custom storage with standard OAuth
standard_oauth = RubyLLM::MCP::Auth::OAuthProvider.new(
  server_url: SERVER_URL,
  redirect_uri: "http://localhost:8080/callback",
  scope: SCOPES,
  storage: storage  # Same storage instance can be shared
)

puts "Standard OAuth created with same custom storage"
puts "Tokens are shared across different OAuth provider instances"

# The stored token is accessible from both providers
token_from_standard = standard_oauth.access_token
puts "\n✓ Token accessible from standard provider: #{token_from_standard ? 'Yes' : 'No'}"

puts "\n" + "=" * 60
puts "Custom Storage Benefits:"
puts "-" * 60
puts "✓ Persist tokens across application restarts"
puts "✓ Share tokens across multiple processes"
puts "✓ Encrypt sensitive token data"
puts "✓ Implement custom expiration logic"
puts "✓ Add logging and monitoring"
puts "✓ Support multi-user systems"
puts "✓ Integrate with existing authentication systems"

puts "\n" + "=" * 60
puts "Real-World Storage Examples:"
puts "-" * 60
puts <<~EXAMPLES
  # Database (ActiveRecord)
  class DatabaseStorage
    def set_token(server_url, token)
      OAuthToken.create!(
        server_url: server_url,
        access_token: encrypt(token.access_token),
        refresh_token: encrypt(token.refresh_token),
        expires_at: token.expires_at
      )
    end

    def get_token(server_url)
      record = OAuthToken.find_by(server_url: server_url)
      return nil unless record

      Token.new(
        access_token: decrypt(record.access_token),
        refresh_token: decrypt(record.refresh_token),
        expires_in: (record.expires_at - Time.now).to_i
      )
    end
  end

  # Redis
  class RedisStorage
    def set_token(server_url, token)
      redis.setex(
        "oauth:\#{server_url}",
        token.expires_in,
        JSON.generate(token.to_h)
      )
    end

    def get_token(server_url)
      data = redis.get("oauth:\#{server_url}")
      return nil unless data

      Token.from_h(JSON.parse(data))
    end
  end
EXAMPLES

puts "=" * 60
