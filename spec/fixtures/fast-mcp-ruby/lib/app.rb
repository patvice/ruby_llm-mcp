# frozen_string_literal: true

# Example of using MCP as a Rack middleware
#
# Docker Configuration:
# - Set DOCKER=true or use BIND=tcp://0.0.0.0:3006 to enable Docker mode
# - Docker mode allows connections from Docker bridge networks (172.17.0.1, etc.)
# - Without Docker mode, only localhost connections are allowed for security

require "bundler/setup"
Bundler.require(:default)
require "fast_mcp"
require "rack"
require "rack/handler/puma"

is_silent = ARGV.include?("--silent")
port = ENV.fetch("PORT", 3006)

# Also detect CI environments
is_ci = ENV["CI"] == "true" || ENV["GITHUB_ACTIONS"] == "true"

allowed_ips = if is_ci
                # Allow more IPs in CI environments
                ["127.0.0.1", "::1", "localhost", "172.17.0.1", "172.18.0.1", "10.0.0.0/8", "192.168.0.0/16"]
              else
                # Default to localhost only
                ["127.0.0.1", "::1", "localhost"]
              end

class NullWriter
  def write(*args)
    args.map(&:to_s).sum(&:length)
  end

  def closed?
    false
  end

  def puts(*args); end
  def print(*args); end
  def printf(*args); end
  def sync; end
  def flush; end
  def close; end
end

class NullLogger
  def debug(*); end
  def info(*); end
  def warn(*); end
  def error(*); end
  def fatal(*); end
  def unknown(*); end
end

# Health check middleware
class HealthCheckMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["PATH_INFO"] == "/health"
      [200, { "Content-Type" => "application/json" }, [{ status: "healthy", timestamp: Time.now.iso8601 }.to_json]]
    else
      @app.call(env)
    end
  end
end

# Define tools using the class inheritance approach
class GreetTool < FastMcp::Tool
  description "Greet a person"

  arguments do
    required(:name).filled(:string).description("The name of the person to greet")
  end

  def call(name:)
    "Hello, #{name}!"
  end
end

class CalculateTool < FastMcp::Tool
  description "Perform a calculation"

  arguments do
    required(:operation).filled(:string).value(included_in?: %w[add subtract multiply
                                                                divide]).description("The operation to perform")
    required(:x).filled(:float).description("The first number")
    required(:y).filled(:float).description("The second number")
  end

  def call(operation:, x:, y:) # rubocop:disable Naming/MethodParameterName
    case operation
    when "add"
      x + y
    when "subtract"
      x - y
    when "multiply"
      x * y
    when "divide"
      x / y
    else
      raise "Unknown operation: #{operation}"
    end
  end
end

class HelloWorldResource < FastMcp::Resource
  uri "file://hello_world"
  resource_name "Hello World"
  description "A simple hello world program"
  mime_type "text/plain"

  def content
    'puts "Hello, world!"'
  end
end

# Create a simple Rack application
app = lambda do |_env|
  [200, { "Content-Type" => "text/html" },
   ["<html><body><h1>Hello from Rack!</h1><p>This is a simple Rack app with MCP middleware.</p></body></html>"]]
end

# Create the MCP middleware
mcp_app = FastMcp.rack_middleware(
  app,
  name: "fast-mcp-ruby", version: "1.0.0",
  logger: is_silent ? NullLogger.new : Logger.new($stdout),
  # Configure IP restrictions based on environment
  allowed_origins: allowed_ips,
  localhost_only: !is_ci
) do |server|
  # Register tool classes
  server.register_tools(GreetTool, CalculateTool)

  # Register a sample resource
  server.register_resource(HelloWorldResource)
end

# Choose bind address based on environment
bind_address = if is_ci
                 "0.0.0.0:#{port}"
               else
                 "127.0.0.1:#{port}"
               end

unless is_silent
  # Run the Rack application with MCP middleware
  puts "Starting Rack application with MCP middleware on http://#{}"
  puts "Docker mode: #{is_docker_or_ci ? 'enabled' : 'disabled'}"
  puts "Allowed IPs: #{allowed_ips.join(', ')}"
  puts "MCP endpoints:"
  puts "  - http://#{bind_address}/mcp/sse (SSE endpoint)"
  puts "  - http://#{bind_address}/mcp/messages (JSON-RPC endpoint)"
  puts "  - http://#{bind_address}/health (Health check endpoint)"
  puts "Press Ctrl+C to stop"
end

# Use the Puma server directly instead of going through Rack::Handler
require "puma"
require "puma/configuration"
require "puma/launcher"

app = Rack::Builder.new do
  use HealthCheckMiddleware
  run mcp_app
end

log_writer = is_silent ? Puma::LogWriter.new(NullWriter.new, NullWriter.new) : Puma::LogWriter.stdio

config = Puma::Configuration.new(log_writer: log_writer) do |user_config|
  user_config.bind "tcp://#{bind_address}"
  user_config.app app
end

launcher = Puma::Launcher.new(config, log_writer: log_writer)
launcher.run
