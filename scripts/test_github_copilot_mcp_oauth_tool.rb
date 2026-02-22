#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require "logger"
require "time"

require "ruby_llm/mcp"

READ_ONLY_NAME_PATTERN = /(list|get|search|find|read|whoami|status|info|show|fetch)/i
PREFERRED_SELF_TEST_PATTERN = /(whoami|me|profile|status|health|ping|user)/i
DEPRIORITIZED_PATTERN = /(team|org|repo|admin|write|delete|create|update)/i

# OAuth + MCP settings (edit these directly)
SERVER_URL = "https://api.githubcopilot.com/mcp"
OAUTH_SCOPE = nil
OAUTH_CALLBACK_PORT = 3333
OAUTH_CALLBACK_PATH = "/callback"
OAUTH_REDIRECT_URI = nil
OAUTH_TIMEOUT = 300
OAUTH_CLIENT_ID = nil
OAUTH_CLIENT_SECRET = nil
OAUTH_TOKEN_ENDPOINT_AUTH_METHOD = nil
AUTO_OPEN_BROWSER = true
DEBUG_LOGS = false

# Tool execution settings
MCP_TEST_TOOL = nil
MCP_TEST_TOOL_ARGS_JSON = nil
STRICT_TOOL_SUCCESS = false

def fail!(message)
  warn "FAIL: #{message}"
  exit 1
end

def required_params(schema)
  return [] unless schema.is_a?(Hash)
  return [] unless schema["required"].is_a?(Array)

  schema["required"].map(&:to_s)
end

def pick_schema_type(schema)
  type = schema["type"]
  if type.is_a?(Array)
    type.find { |entry| entry != "null" } || type.first
  else
    type
  end
end

def sample_special_value(schema, key_name)
  format = schema["format"]
  return Time.now.utc.iso8601 if format == "date-time"
  return "https://example.com" if format == "uri" || key_name.to_s.match?(/(uri|url)\z/i)
  return "tester@example.com" if key_name.to_s.match?(/email/i)

  nil
end

def sample_value(schema, key_name = "value")
  return "test" unless schema.is_a?(Hash)

  return schema["const"] if schema.key?("const")
  return schema["default"] if schema.key?("default")
  return schema["examples"].first if schema["examples"].is_a?(Array) && !schema["examples"].empty?
  return schema["enum"].first if schema["enum"].is_a?(Array) && !schema["enum"].empty?

  %w[oneOf anyOf allOf].each do |selector|
    options = schema[selector]
    return sample_value(options.first, key_name) if options.is_a?(Array) && !options.empty?
  end
  schema_type = pick_schema_type(schema)
  special = sample_special_value(schema, key_name)
  return special unless special.nil?

  case schema_type
  when "boolean"
    false
  when "integer"
    1
  when "number"
    1.0
  when "array"
    item_schema = schema["items"]
    item_schema.is_a?(Hash) ? [sample_value(item_schema, key_name)] : []
  when "object"
    props = schema["properties"].is_a?(Hash) ? schema["properties"] : {}
    required = required_params(schema)
    required.each_with_object({}) do |required_key, generated|
      generated[required_key] = sample_value(props[required_key], required_key)
    end
  else
    key_name.to_s.match?(/id\z/i) ? "test-id" : "test"
  end
end

def build_params_for_tool(tool, args_json: nil)
  if args_json && !args_json.empty?
    parsed = JSON.parse(args_json)
    unless parsed.is_a?(Hash)
      raise ArgumentError, "MCP_TEST_TOOL_ARGS_JSON must be a JSON object"
    end

    return parsed.transform_keys(&:to_sym)
  end

  schema = tool.params_schema
  return {} unless schema.is_a?(Hash)

  props = schema["properties"].is_a?(Hash) ? schema["properties"] : {}
  required = required_params(schema)

  required.each_with_object({}) do |required_key, generated|
    generated[required_key.to_sym] = sample_value(props[required_key], required_key)
  end
end

def tool_score(tool)
  score = 0
  score += 80 if tool.name.to_s.match?(PREFERRED_SELF_TEST_PATTERN)
  score += 100 if tool.annotations&.read_only_hint
  score += 30 if tool.name.to_s.match?(READ_ONLY_NAME_PATTERN)
  score += 20 if required_params(tool.params_schema).empty?
  score -= 40 if tool.name.to_s.match?(DEPRIORITIZED_PATTERN)
  score
end

def pick_tool(tools, explicit_name = nil)
  if explicit_name && !explicit_name.empty?
    tool = tools.find { |entry| entry.name == explicit_name }
    fail!("Tool '#{explicit_name}' was not found. Available: #{tools.map(&:name).join(', ')}") unless tool

    return tool
  end

  tools.max_by { |tool| [tool_score(tool), tool.name] }
end

def print_tool_summary(tools)
  puts "Tools (#{tools.length}):"
  tools.each do |tool|
    req = required_params(tool.params_schema)
    req_text = req.empty? ? "none" : req.join(", ")
    puts "  - #{tool.name} (required: #{req_text})"
  end
end

server_url = SERVER_URL
scope = OAUTH_SCOPE
callback_port = OAUTH_CALLBACK_PORT
callback_path = OAUTH_CALLBACK_PATH
redirect_uri = OAUTH_REDIRECT_URI || "http://localhost:#{callback_port}#{callback_path}"
oauth_timeout = OAUTH_TIMEOUT
tool_name = MCP_TEST_TOOL
tool_args_json = MCP_TEST_TOOL_ARGS_JSON
strict_tool_success = STRICT_TOOL_SUCCESS
auto_open_browser = AUTO_OPEN_BROWSER
oauth_client_id = OAUTH_CLIENT_ID
oauth_client_secret = OAUTH_CLIENT_SECRET
oauth_token_endpoint_auth_method = OAUTH_TOKEN_ENDPOINT_AUTH_METHOD

RubyLLM::MCP.configure do |config|
  config.log_level = DEBUG_LOGS ? Logger::DEBUG : Logger::INFO
  config.oauth.client_name = "RubyLLM MCP GitHub Copilot verifier"
end

puts "GitHub Copilot MCP OAuth Test"
puts "-" * 60
puts "Server URL: #{server_url}"
puts "Scope: #{scope || '(server default)'}"
puts "Callback: #{redirect_uri}"
puts "OAuth client mode: #{oauth_client_id ? 'pre-registered client' : 'dynamic registration'}"
puts

storage = RubyLLM::MCP::Auth::MemoryStorage.new

# Optional: seed storage with pre-registered OAuth client info for providers
# that do not support RFC 7591 dynamic client registration.
if oauth_client_id && !oauth_client_id.empty?
  auth_method = if oauth_token_endpoint_auth_method && !oauth_token_endpoint_auth_method.empty?
                  oauth_token_endpoint_auth_method
                elsif oauth_client_secret && !oauth_client_secret.empty?
                  "client_secret_post"
                else
                  "none"
                end

  storage.set_client_info(
    server_url,
    RubyLLM::MCP::Auth::ClientInfo.new(
      client_id: oauth_client_id,
      client_secret: oauth_client_secret,
      metadata: RubyLLM::MCP::Auth::ClientMetadata.new(
        redirect_uris: [redirect_uri],
        token_endpoint_auth_method: auth_method,
        grant_types: %w[authorization_code refresh_token],
        response_types: ["code"],
        scope: scope
      )
    )
  )
end

oauth = RubyLLM::MCP::Auth.create_oauth(
  server_url,
  type: :browser,
  callback_port: callback_port,
  callback_path: callback_path,
  redirect_uri: redirect_uri,
  scope: scope,
  storage: storage,
  logger: RubyLLM::MCP.logger
)

client = nil

begin
  puts "Step 1/4: Authenticating with browser OAuth..."
  token = oauth.authenticate(timeout: oauth_timeout, auto_open_browser: auto_open_browser)
  puts "OAuth token acquired (expires_at=#{token.expires_at || 'n/a'})"
  puts

  puts "Step 2/4: Connecting to MCP endpoint..."
  client = RubyLLM::MCP.client(
    name: "github-copilot-mcp-test",
    transport_type: :streamable,
    start: false,
    config: {
      url: server_url,
      oauth: {
        provider: oauth,
        scope: scope
      }
    }
  )

  client.start
  puts "Connected."
  puts

  puts "Step 3/4: Fetching tools..."
  tools = client.tools
  fail!("No tools returned by server. Verify OAuth scope and server permissions.") if tools.empty?

  print_tool_summary(tools)
  puts

  puts "Step 4/4: Executing one tool..."
  selected_tool = pick_tool(tools, tool_name)
  params = build_params_for_tool(selected_tool, args_json: tool_args_json)

  puts "Selected tool: #{selected_tool.name}"
  puts "Params: #{params.empty? ? '{}' : JSON.pretty_generate(params)}"
  puts

  result = begin
    selected_tool.execute(**params)
  rescue RubyLLM::MCP::Errors::AuthenticationRequiredError
    puts "Tool call requires additional OAuth authorization. Re-authenticating..."
    oauth.authenticate(timeout: oauth_timeout, auto_open_browser: auto_open_browser)
    selected_tool.execute(**params)
  end

  error_message = if result.is_a?(Hash)
                    result[:error] || result["error"]
                  end

  if error_message
    puts "Tool round-trip completed, but the tool returned an error payload:"
    puts "  #{error_message}"
    fail!("Strict mode enabled (STRICT_TOOL_SUCCESS=1).") if strict_tool_success

    puts
    puts "PASS: OAuth + tools/list + tools/call are working at protocol level."
    exit 0
  end

  puts "Tool call succeeded."
  puts "Result preview:"
  puts result.to_s[0, 800]
  puts
  puts "PASS: GitHub Copilot MCP integration verified."
rescue JSON::ParserError => e
  fail!("Invalid JSON in MCP_TEST_TOOL_ARGS_JSON: #{e.message}")
rescue RubyLLM::MCP::Errors::TimeoutError => e
  fail!("Timeout: #{e.message}")
rescue RubyLLM::MCP::Errors::TransportError => e
  fail!("Transport error: #{e.message}")
rescue StandardError => e
  fail!("Unexpected error (#{e.class}): #{e.message}")
ensure
  client&.stop
end
