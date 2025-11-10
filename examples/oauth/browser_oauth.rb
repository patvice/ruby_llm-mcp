#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating Browser OAuth flow
# This is the simplest OAuth approach - automatically opens browser and handles callback
# Usage: ruby examples/oauth/browser_oauth.rb

require "bundler/setup"
require "ruby_llm/mcp"

# Configure MCP logging (optional)
RubyLLM::MCP.configure do |config|
  config.log_level = Logger::INFO
end

# Example OAuth server (Google in this case)
# Replace with your OAuth provider's details
SERVER_URL = "https://accounts.google.com"
CLIENT_ID = ENV.fetch("OAUTH_CLIENT_ID", "your_client_id_here")
CLIENT_SECRET = ENV.fetch("OAUTH_CLIENT_SECRET", "your_client_secret_here")
SCOPES = "openid profile email"

puts "Browser OAuth Example"
puts "=" * 60

# Create BrowserOAuthProvider
# This will automatically open a browser and handle the OAuth callback
browser_oauth = RubyLLM::MCP::Auth::BrowserOAuthProvider.new(
  server_url: SERVER_URL,
  callback_port: 8080,
  callback_path: "/callback",
  redirect_uri: "http://localhost:8080/callback",
  scope: SCOPES
)

puts "\nConfiguration:"
puts "  OAuth Server: #{SERVER_URL}"
puts "  Callback URL: http://localhost:#{browser_oauth.callback_port}#{browser_oauth.callback_path}"
puts "  Scopes: #{SCOPES}"
puts "\nNote: Set OAUTH_CLIENT_ID and OAUTH_CLIENT_SECRET environment variables"
puts "=" * 60

# Uncomment to test authentication:
# begin
#   puts "\nStarting authentication flow..."
#   puts "Browser will open automatically. Please authorize the application."
#
#   # This will:
#   # 1. Start a local callback server
#   # 2. Open the browser to the OAuth authorization page
#   # 3. Wait for the user to authorize
#   # 4. Handle the callback and exchange code for token
#   # 5. Return the access token
#   token = browser_oauth.authenticate(timeout: 300)
#
#   puts "\n✓ Authentication successful!"
#   puts "Access Token: #{token.access_token[0..20]}..."
#   puts "Token Type: #{token.token_type}"
#   puts "Expires In: #{token.expires_in} seconds" if token.expires_in
#   puts "Scope: #{token.scope}" if token.scope
#
#   # Token is automatically stored in memory and can be retrieved later
#   stored_token = browser_oauth.access_token
#   puts "\n✓ Token stored and can be retrieved: #{stored_token == token}"
#
# rescue RubyLLM::MCP::Errors::TimeoutError => e
#   puts "\n✗ Authentication timed out: #{e.message}"
# rescue RubyLLM::MCP::Errors::TransportError => e
#   puts "\n✗ Authentication failed: #{e.message}"
# rescue StandardError => e
#   puts "\n✗ Error: #{e.message}"
#   puts e.backtrace.first(5).join("\n")
# end

puts "\n#{'=' * 60}"
puts "To test this example:"
puts "1. Set up OAuth credentials with your provider"
puts "2. Export environment variables:"
puts "   export OAUTH_CLIENT_ID='your_client_id'"
puts "   export OAUTH_CLIENT_SECRET='your_client_secret'"
puts "3. Configure redirect URI: http://localhost:8080/callback"
puts "4. Uncomment the authentication code above"
puts "5. Run: ruby #{__FILE__}"
puts "=" * 60
