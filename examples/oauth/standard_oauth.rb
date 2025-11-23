#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating Standard OAuth flow
# This approach gives you full control over the authorization flow
# Useful for web applications or when you need custom callback handling
# Usage: ruby examples/oauth/standard_oauth.rb

require "bundler/setup"
require "ruby_llm/mcp"

# Configure MCP logging (optional)
RubyLLM::MCP.configure do |config|
  config.log_level = Logger::INFO
end

# Example OAuth server (Google in this case)
SERVER_URL = "https://accounts.google.com"
CLIENT_ID = ENV.fetch("OAUTH_CLIENT_ID", "your_client_id_here")
CLIENT_SECRET = ENV.fetch("OAUTH_CLIENT_SECRET", "your_client_secret_here")
REDIRECT_URI = "http://localhost:8080/callback"
SCOPES = "openid profile email"

puts "Standard OAuth Flow Example"
puts "=" * 60

# Create OAuthProvider
oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
  server_url: SERVER_URL,
  redirect_uri: REDIRECT_URI,
  scope: SCOPES
)

puts "\nConfiguration:"
puts "  OAuth Server: #{SERVER_URL}"
puts "  Redirect URI: #{REDIRECT_URI}"
puts "  Scopes: #{SCOPES}"
puts "=" * 60

# Step 1: Start the authorization flow
puts "\nStep 1: Generate Authorization URL"
puts "-" * 60

auth_url = oauth_provider.start_authorization_flow
puts "Authorization URL generated:"
puts auth_url
puts "\nIn a real application, you would:"
puts "  1. Redirect the user to this URL"
puts "  2. User authorizes your application"
puts "  3. OAuth provider redirects back to your redirect_uri with 'code' and 'state'"

# Step 2: Complete the flow (after receiving callback)
puts "\n#{'-' * 60}"
puts "Step 2: Complete Authorization (after callback)"
puts "-" * 60
puts "After the user authorizes, you'll receive:"
puts "  - code: The authorization code"
puts "  - state: The state parameter (for CSRF protection)"
puts "\nExample callback URL:"
puts "  #{REDIRECT_URI}?code=AUTHORIZATION_CODE&state=STATE_VALUE"

# Uncomment to test with actual OAuth:
# puts "\nWaiting for you to authorize..."
# puts "1. Visit the URL above in your browser"
# puts "2. Authorize the application"
# puts "3. Copy the 'code' parameter from the redirect URL"
# print "\nEnter authorization code: "
# code = gets.chomp
#
# print "Enter state parameter: "
# state = gets.chomp
#
# begin
#   # Exchange code for token
#   token = oauth_provider.complete_authorization_flow(code, state)
#
#   puts "\n✓ Token exchange successful!"
#   puts "Access Token: #{token.access_token[0..20]}..."
#   puts "Token Type: #{token.token_type}"
#   puts "Expires In: #{token.expires_in} seconds" if token.expires_in
#   puts "Refresh Token: #{token.refresh_token ? 'Present' : 'Not provided'}"
#   puts "Scope: #{token.scope}" if token.scope
#
#   # Token is automatically stored and can be retrieved
#   stored_token = oauth_provider.access_token
#   puts "\n✓ Token stored successfully: #{stored_token == token}"
#
#   # The token will be automatically refreshed when it expires (if refresh_token is available)
#   puts "\nToken management:"
#   puts "  Expired?: #{token.expired?}"
#   puts "  Expires soon?: #{token.expires_soon?}"
#
# rescue RubyLLM::MCP::Errors::TransportError => e
#   puts "\n✗ Token exchange failed: #{e.message}"
# rescue StandardError => e
#   puts "\n✗ Error: #{e.message}"
# end

puts "\n#{'=' * 60}"
puts "Integration with Web Applications:"
puts "-" * 60
puts "In a Rails/Sinatra app, you would:"
puts ""
puts "# In your authorization route:"
puts "get '/auth/oauth' do"
puts "  auth_url = oauth_provider.start_authorization_flow"
puts "  redirect auth_url"
puts "end"
puts ""
puts "# In your callback route:"
puts "get '/callback' do"
puts "  code = params[:code]"
puts "  state = params[:state]"
puts "  token = oauth_provider.complete_authorization_flow(code, state)"
puts "  session[:user_token] = token.access_token"
puts "  redirect '/dashboard'"
puts "end"
puts "=" * 60

puts "\nTo test this example:"
puts "1. Set up OAuth credentials with your provider"
puts "2. Export environment variables:"
puts "   export OAUTH_CLIENT_ID='your_client_id'"
puts "   export OAUTH_CLIENT_SECRET='your_client_secret'"
puts "3. Configure redirect URI: #{REDIRECT_URI}"
puts "4. Uncomment the interactive code above"
puts "5. Run: ruby #{__FILE__}"
puts "=" * 60



