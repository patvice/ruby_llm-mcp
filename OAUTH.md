# OAuth 2.1 Support in ruby_llm-mcp

This gem implements comprehensive OAuth 2.1 support for MCP (Model Context Protocol) servers, providing secure authentication and authorization for HTTP-based transports (SSE and StreamableHTTP).

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Browser-Based Authentication](#browser-based-authentication)
- [Custom Storage](#custom-storage)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

## Features

### OAuth 2.1 Compliance

- ✅ **PKCE (RFC 7636)**: Mandatory Proof Key for Code Exchange with S256 (SHA256)
- ✅ **Dynamic Client Registration (RFC 7591)**: Automatic client registration with OAuth servers
- ✅ **Server Discovery (RFC 8414)**: Automatic authorization server metadata discovery
- ✅ **Protected Resource Metadata (RFC 9728)**: Support for delegated authorization servers
- ✅ **Resource Indicators (RFC 8707)**: Token binding to specific MCP servers
- ✅ **State Parameter**: CSRF protection for authorization flows
- ✅ **Automatic Token Refresh**: Proactive token refresh with 5-minute buffer
- ✅ **Secure Token Storage**: Pluggable storage with in-memory default

### Transport Support

- **SSE (Server-Sent Events)**: Full OAuth support for event streams and message endpoints
- **StreamableHTTP**: Complete OAuth integration with session management
- **Stdio**: Not applicable (local process communication)

## Architecture

### Core Components

```
┌─────────────────────────────────────┐
│         OAuth Provider              │
│  (Discovery, Registration, Tokens)  │
├─────────────────────────────────────┤
│         Browser OAuth               │
│  (Local callback server)            │
├─────────────────────────────────────┤
│         Storage Layer               │
│  (Tokens, Client Info, Metadata)    │
├─────────────────────────────────────┤
│         Transport Layer             │
│  (SSE, StreamableHTTP)             │
└─────────────────────────────────────┘
```

### OAuth Flow

```
1. Client Configuration → OAuth Provider Creation
2. Server Discovery → Authorization Server Metadata
3. Client Registration → Client ID & Client Secret
4. Authorization Request → PKCE + State Generation
5. User Authorization → Browser/Manual
6. Token Exchange → Access Token + Refresh Token
7. API Requests → Automatic Token Refresh
```

## Quick Start

### Basic Configuration

Add OAuth configuration to your MCP client:

```ruby
require "ruby_llm/mcp"

client = RubyLLM::MCP.client(
  name: "oauth-mcp-server",
  transport_type: :sse,  # or :streamable
  config: {
    url: "https://mcp.example.com/api",
    oauth: {
      redirect_uri: "http://localhost:8080/callback",
      scope: "mcp:read mcp:write"
    }
  }
)
```

### File-Based Configuration

Create `config/mcp_servers.yml`:

```yaml
mcp_servers:
  protected_server:
    transport_type: streamable
    url: https://mcp.example.com/api
    oauth:
      redirect_uri: http://localhost:8080/callback
      scope: mcp:read mcp:write
```

Load configuration:

```ruby
RubyLLM.configure do |config|
  config.config_path = "config/mcp_servers.yml"
end

RubyLLM::MCP.establish_connection
```

## Configuration

### OAuth Configuration Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `redirect_uri` | String | No | Callback URL for authorization (default: `http://localhost:8080/callback`) |
| `scope` | String | No | OAuth scopes to request (e.g., `"mcp:read mcp:write"`) |
| `storage` | Object | No | Custom storage implementation (default: in-memory) |

### Environment Variables

Use ERB in configuration files for sensitive data:

```yaml
mcp_servers:
  production_server:
    transport_type: streamable
    url: <%= ENV['MCP_SERVER_URL'] %>
    oauth:
      redirect_uri: <%= ENV['OAUTH_REDIRECT_URI'] %>
      scope: <%= ENV['OAUTH_SCOPE'] %>
```

## Usage Examples

### Example 1: Simple SSE Client with OAuth

```ruby
require "ruby_llm/mcp"
require "ruby_llm/mcp/auth/browser_oauth"

# Create client with OAuth
client = RubyLLM::MCP.client(
  name: "secure-server",
  transport_type: :sse,
  start: false,  # Don't auto-start
  config: {
    url: "https://mcp.example.com/sse",
    oauth: {
      redirect_uri: "http://localhost:8080/callback",
      scope: "mcp:read mcp:write"
    }
  }
)

# Get OAuth provider from transport
transport = client.instance_variable_get(:@coordinator).send(:transport)
oauth_provider = transport.oauth_provider

# Perform browser-based authentication
browser_oauth = RubyLLM::MCP::Auth::BrowserOAuth.new(
  oauth_provider,
  callback_port: 8080,
  callback_path: "/callback"
)

# This will:
# 1. Start local callback server
# 2. Open browser to authorization URL
# 3. Wait for user to authorize
# 4. Exchange code for token
# 5. Store token
token = browser_oauth.authenticate(timeout: 300, auto_open_browser: true)

puts "Successfully authenticated!"
puts "Access token: #{token.access_token[0..20]}..."

# Now start the client - it will use the stored token
client.start

# Use the client normally
tools = client.tools
puts "Available tools: #{tools.map(&:name).join(', ')}"
```

### Example 2: StreamableHTTP with OAuth

```ruby
require "ruby_llm/mcp"

client = RubyLLM::MCP.client(
  name: "streamable-server",
  transport_type: :streamable,
  start: false,
  config: {
    url: "https://api.example.com/mcp",
    oauth: {
      redirect_uri: "http://localhost:9000/callback",
      scope: "mcp:full"
    }
  }
)

# Authenticate (same as above)
transport = client.instance_variable_get(:@coordinator).send(:transport)
browser_oauth = RubyLLM::MCP::Auth::BrowserOAuth.new(
  transport.oauth_provider,
  callback_port: 9000
)
browser_oauth.authenticate

# Start client
client.start

# Execute tools
result = client.tool("search").execute(params: { query: "Ruby MCP" })
puts result
```

### Example 3: Manual Authorization Flow

For scenarios where browser opening isn't possible:

```ruby
require "ruby_llm/mcp"

client = RubyLLM::MCP.client(
  name: "manual-auth",
  transport_type: :sse,
  start: false,
  config: {
    url: "https://mcp.example.com/api",
    oauth: {
      redirect_uri: "http://localhost:8080/callback",
      scope: "mcp:read"
    }
  }
)

transport = client.instance_variable_get(:@coordinator).send(:transport)
oauth_provider = transport.oauth_provider

# Start authorization flow
auth_url = oauth_provider.start_authorization_flow

puts "\nPlease visit this URL to authorize:"
puts auth_url
puts "\nAfter authorization, you'll be redirected to:"
puts "#{oauth_provider.redirect_uri}?code=...&state=..."
puts "\nEnter the 'code' parameter from the URL:"

code = gets.chomp

puts "Enter the 'state' parameter:"
state = gets.chomp

# Complete authorization
token = oauth_provider.complete_authorization_flow(code, state)
puts "\nAuthentication successful!"

# Start client
client.start
```

### Example 4: Multiple Clients with Different Auth

```ruby
require "ruby_llm/mcp"

RubyLLM.configure do |config|
  config.mcp_configuration = [
    {
      name: "public-server",
      transport_type: :stdio,
      config: {
        command: "mcp-server-filesystem",
        args: ["/tmp"]
      }
    },
    {
      name: "secure-server-1",
      transport_type: :sse,
      start: false,
      config: {
        url: "https://secure1.example.com",
        oauth: {
          redirect_uri: "http://localhost:8080/callback",
          scope: "mcp:read"
        }
      }
    },
    {
      name: "secure-server-2",
      transport_type: :streamable,
      start: false,
      config: {
        url: "https://secure2.example.com",
        oauth: {
          redirect_uri: "http://localhost:8081/callback",
          scope: "mcp:admin"
        }
      }
    }
  ]
end

# Start public server immediately
RubyLLM::MCP.establish_connection do |clients|
  # public-server auto-starts
  puts "Public server tools: #{clients[:public_server].tools.count}"
end

# Authenticate secure servers separately
def authenticate_client(client, port)
  transport = client.instance_variable_get(:@coordinator).send(:transport)
  browser_oauth = RubyLLM::MCP::Auth::BrowserOAuth.new(
    transport.oauth_provider,
    callback_port: port
  )
  browser_oauth.authenticate
  client.start
end

clients = RubyLLM::MCP.clients
authenticate_client(clients[:secure_server_1], 8080)
authenticate_client(clients[:secure_server_2], 8081)

# Now all clients are ready
RubyLLM::MCP.tools.each do |tool|
  puts "Tool: #{tool.name}"
end
```

## Browser-Based Authentication

The `BrowserOAuth` class provides a complete browser-based OAuth flow:

### Features

- **Automatic Browser Opening**: Opens default browser to authorization URL
- **Local Callback Server**: Pure Ruby TCP server (no external dependencies)
- **Beautiful UI**: Styled HTML success/error pages
- **Cross-Platform**: Supports macOS, Linux, Windows
- **Timeout Support**: Configurable timeout for user authorization
- **Thread-Safe**: Safe for concurrent use

### Usage

```ruby
require "ruby_llm/mcp/auth/browser_oauth"

# Create OAuth provider
oauth_provider = RubyLLM::MCP::Auth::OAuthProvider.new(
  server_url: "https://mcp.example.com",
  redirect_uri: "http://localhost:8080/callback",
  scope: "mcp:read mcp:write"
)

# Create browser OAuth helper
browser_oauth = RubyLLM::MCP::Auth::BrowserOAuth.new(
  oauth_provider,
  callback_port: 8080,
  callback_path: "/callback"
)

# Authenticate (opens browser automatically)
begin
  token = browser_oauth.authenticate(
    timeout: 300,              # 5 minutes
    auto_open_browser: true    # Set to false for manual opening
  )

  puts "Access token: #{token.access_token}"
  puts "Expires at: #{token.expires_at}"
  puts "Refresh token: #{token.refresh_token}" if token.refresh_token
rescue RubyLLM::MCP::Errors::TimeoutError
  puts "Authorization timed out"
rescue RubyLLM::MCP::Errors::TransportError => e
  puts "Authorization failed: #{e.message}"
end
```

### Custom Callback Port

If port 8080 is in use:

```ruby
browser_oauth = RubyLLM::MCP::Auth::BrowserOAuth.new(
  oauth_provider,
  callback_port: 9999,
  callback_path: "/oauth/callback"
)

# Update OAuth provider redirect URI to match
oauth_provider.redirect_uri = "http://localhost:9999/oauth/callback"
```

## Custom Storage

Implement custom storage for production deployments:

### Storage Interface

```ruby
class CustomStorage
  # Token storage
  def get_token(server_url); end
  def set_token(server_url, token); end

  # Client registration storage
  def get_client_info(server_url); end
  def set_client_info(server_url, client_info); end

  # Server metadata caching
  def get_server_metadata(server_url); end
  def set_server_metadata(server_url, metadata); end

  # PKCE state management (temporary)
  def get_pkce(server_url); end
  def set_pkce(server_url, pkce); end
  def delete_pkce(server_url); end

  # State parameter management (temporary)
  def get_state(server_url); end
  def set_state(server_url, state); end
  def delete_state(server_url); end
end
```

### Example: Redis Storage

```ruby
require "redis"
require "json"

class RedisOAuthStorage
  def initialize(redis_url = ENV["REDIS_URL"])
    @redis = Redis.new(url: redis_url)
  end

  def get_token(server_url)
    data = @redis.get("oauth:token:#{server_url}")
    data ? RubyLLM::MCP::Auth::Token.from_h(JSON.parse(data, symbolize_names: true)) : nil
  end

  def set_token(server_url, token)
    @redis.set("oauth:token:#{server_url}", token.to_h.to_json)
    @redis.expire("oauth:token:#{server_url}", 86400) # 24 hours
  end

  def get_client_info(server_url)
    data = @redis.get("oauth:client:#{server_url}")
    data ? RubyLLM::MCP::Auth::ClientInfo.from_h(JSON.parse(data, symbolize_names: true)) : nil
  end

  def set_client_info(server_url, client_info)
    @redis.set("oauth:client:#{server_url}", client_info.to_h.to_json)
  end

  # ... implement other methods ...
end

# Use custom storage
client = RubyLLM::MCP.client(
  name: "redis-backed",
  transport_type: :sse,
  config: {
    url: "https://mcp.example.com",
    oauth: {
      storage: RedisOAuthStorage.new,
      scope: "mcp:read"
    }
  }
)
```

### Example: Database Storage

```ruby
class DatabaseOAuthStorage
  def initialize(db_connection)
    @db = db_connection
  end

  def get_token(server_url)
    record = @db[:oauth_tokens].where(server_url: server_url).first
    return nil unless record

    RubyLLM::MCP::Auth::Token.from_h(JSON.parse(record[:token_data], symbolize_names: true))
  end

  def set_token(server_url, token)
    @db[:oauth_tokens].insert_conflict(
      target: :server_url,
      update: { token_data: token.to_h.to_json, updated_at: Time.now }
    ).insert(
      server_url: server_url,
      token_data: token.to_h.to_json,
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  # ... implement other methods ...
end
```

## Security Considerations

### PKCE (Proof Key for Code Exchange)

All OAuth flows use PKCE with S256 (SHA256) hashing:

- **Code Verifier**: 32 bytes of cryptographically secure random data
- **Code Challenge**: SHA256 hash of the verifier
- **Protection**: Prevents authorization code interception attacks

### State Parameter

CSRF protection via state parameter:

- **Generation**: 32 bytes of random data (base64url encoded)
- **Validation**: Strict equality check on callback
- **Storage**: Temporary storage, deleted after flow completion

### Token Security

- **Automatic Refresh**: Tokens refreshed proactively (5-minute buffer before expiration)
- **Secure Storage**: Tokens stored securely via pluggable storage interface
- **HTTPS Only**: OAuth flows require HTTPS endpoints (except localhost)
- **Resource Binding**: RFC 8707 resource indicators prevent token reuse across servers

### URL Normalization

Server URLs are normalized to prevent token confusion:

```
https://MCP.EXAMPLE.COM:443/api/  → https://mcp.example.com/api
http://example.com:80             → http://example.com
```

### Sensitive Data Filtering

Configuration objects automatically filter sensitive data:

```ruby
config = { oauth: { scope: "read", client_secret: "secret123" } }
config.inspect  # client_secret shown as [FILTERED]
```

## Troubleshooting

### Port Already in Use

If callback port is in use:

```ruby
browser_oauth = RubyLLM::MCP::Auth::BrowserOAuth.new(
  oauth_provider,
  callback_port: 8081  # Try different port
)
```

### Browser Doesn't Open

Set `auto_open_browser: false` and manually copy URL:

```ruby
token = browser_oauth.authenticate(auto_open_browser: false)
# Manually open the displayed URL
```

### Token Refresh Fails

Check server logs and ensure refresh tokens are being returned:

```ruby
token = oauth_provider.access_token
if token&.refresh_token
  puts "Refresh token present"
else
  puts "No refresh token - re-authentication required"
end
```

### Discovery Fails

Verify OAuth server endpoints:

```ruby
# Check discovery URLs
discovery_url = "https://mcp.example.com/.well-known/oauth-authorization-server"
response = HTTParty.get(discovery_url)
puts response.body
```

### Custom Redirect URI Not Working

Ensure redirect URI matches exactly:

```ruby
# Server expects
"http://localhost:8080/callback"

# Not
"http://localhost:8080/callback/"  # Trailing slash
"http://127.0.0.1:8080/callback"    # Different host
```

## Advanced Topics

### Custom OAuth Provider

For advanced use cases, create OAuth provider directly:

```ruby
require "ruby_llm/mcp/auth/oauth_provider"

provider = RubyLLM::MCP::Auth::OAuthProvider.new(
  server_url: "https://mcp.example.com",
  redirect_uri: "http://localhost:8080/callback",
  scope: "custom:scope",
  logger: Logger.new($stdout, level: Logger::DEBUG),
  storage: CustomStorage.new
)

# Manual flow control
auth_url = provider.start_authorization_flow
# ... user authorization ...
token = provider.complete_authorization_flow(code, state)
```

### Token Introspection

Check token status:

```ruby
token = oauth_provider.access_token

if token
  puts "Valid: #{!token.expired?}"
  puts "Expires soon: #{token.expires_soon?}"
  puts "Expires at: #{token.expires_at}"
  puts "Scope: #{token.scope}"
end
```

### Logging

Enable debug logging:

```ruby
RubyLLM.configure do |config|
  config.log_level = Logger::DEBUG
end

# Or set environment variable
ENV["RUBYLLM_MCP_DEBUG"] = "1"
```

## License

See [LICENSE](LICENSE) file.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.
