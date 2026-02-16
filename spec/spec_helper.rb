# frozen_string_literal: true

require "debug"
require "dotenv"
require "simplecov"
require "vcr"
require "webmock/rspec"

Dotenv.load

SimpleCov.start do
  add_filter "/spec/"
  add_filter "/examples/"

  enable_coverage :branch
end

require "bundler/setup"
require "ruby_llm"
require "ruby_llm/mcp"
begin
  require "mcp" if RUBY_VERSION >= "3.1.0"
rescue LoadError
  # MCP SDK specs are skipped when the gem is not installed.
end

require_relative "support/client_runner"
require_relative "support/client_sync_helpers"
require_relative "support/test_server_manager"
require_relative "support/mcp_test_configuration"
require_relative "support/simple_multiply_tool"
require_relative "support/adapter_test_helpers"
require_relative "support/time_support"

# VCR Configuration
VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  config.ignore_hosts("localhost")

  record_mode = if ENV["CI"]
                  :none
                elsif ENV["VCR_REFRESH"] == "true"
                  :all
                else
                  :new_episodes
                end

  # Don't record new HTTP interactions when running in CI
  config.default_cassette_options = {
    record: record_mode,
    allow_playback_repeats: true
  }
  config.debug_logger = File.open("vcr_debug.log", "w") if ENV["VCR_DEBUG"] == "true"

  # Create new cassette directory if it doesn't exist
  FileUtils.mkdir_p(config.cassette_library_dir)

  # Allow HTTP connections when necessary - this will fail PRs by design if they don't have cassettes
  config.allow_http_connections_when_no_cassette = !ENV["CI"]

  # Filter out API keys from the recorded cassettes
  config.filter_sensitive_data("<OPENAI_API_KEY>") { ENV.fetch("OPENAI_API_KEY", nil) }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV.fetch("ANTHROPIC_API_KEY", nil) }
  config.filter_sensitive_data("<GEMINI_API_KEY>") { ENV.fetch("GEMINI_API_KEY", nil) }
  config.filter_sensitive_data("<DEEPSEEK_API_KEY>") { ENV.fetch("DEEPSEEK_API_KEY", nil) }
  config.filter_sensitive_data("<OPENROUTER_API_KEY>") { ENV.fetch("OPENROUTER_API_KEY", nil) }

  config.filter_sensitive_data("<AWS_ACCESS_KEY_ID>") { ENV.fetch("AWS_ACCESS_KEY_ID", nil) }
  config.filter_sensitive_data("<AWS_SECRET_ACCESS_KEY>") { ENV.fetch("AWS_SECRET_ACCESS_KEY", nil) }
  config.filter_sensitive_data("<AWS_REGION>") { ENV.fetch("AWS_REGION", "us-west-2") }
  config.filter_sensitive_data("<AWS_SESSION_TOKEN>") { ENV.fetch("AWS_SESSION_TOKEN", nil) }

  config.filter_sensitive_data("<OPENAI_ORGANIZATION>") do |interaction|
    interaction.response.headers["Openai-Organization"]&.first
  end
  config.filter_sensitive_data("<X_REQUEST_ID>") { |interaction| interaction.response.headers["X-Request-Id"]&.first }
  config.filter_sensitive_data("<REQUEST_ID>") { |interaction| interaction.response.headers["Request-Id"]&.first }
  config.filter_sensitive_data("<CF_RAY>") { |interaction| interaction.response.headers["Cf-Ray"]&.first }

  # Filter cookies
  config.before_record do |interaction|
    if interaction.response.headers["Set-Cookie"]
      interaction.response.headers["Set-Cookie"] = interaction.response.headers["Set-Cookie"].map { "<COOKIE>" }
    end
  end
end

FILESYSTEM_CLIENT = {
  name: "filesystem",
  transport_type: :stdio,
  config: {
    command: "bunx",
    args: [
      "@modelcontextprotocol/server-filesystem",
      File.expand_path("..", __dir__) # Allow access to the current directory
    ]
  }
}.freeze

# MCP Adapter Testing Configuration
#
# The test suite supports testing against multiple MCP adapters:
#
# 1. RubyLLMAdapter (Native) - Full-featured native implementation
#    - Supports: tools, prompts, resources, resource_templates, completions,
#                logging, sampling, roots, notifications, progress_tracking,
#                human_in_the_loop, elicitation, subscriptions
#    - Transports: stdio, sse, streamable, streamable_http
#
# 2. MCPSdkAdapter - Wrapper around the official MCP SDK gem
#    - Supports: tools, prompts, resources, resource_templates, logging (basic features)
#    - Transports: stdio, http, streamable, streamable_http
#    - Requires: gem 'mcp', '~> 0.7' (optional - tests will skip if not installed)
#
# Testing DSL:
#   Use `each_client` to run tests on all available adapters
#   Use `each_client(adapter: :native)` to run only on RubyLLMAdapter
#   Use `each_client_supporting(:logging, :sampling)` to run only on adapters with specific features
#
# Example:
#   each_client do |config|
#     it "runs on all 4 clients" do
#       # Test code here
#     end
#   end
#
#   each_client_supporting(:logging) do |config|
#     it "runs only on native clients" do
#       # Test code that requires logging feature
#     end
#   end

native_clients = [
  {
    name: "stdio-native",
    adapter: :ruby_llm,
    options: {
      name: "stdio-native-server",
      adapter: :ruby_llm,
      transport_type: :stdio,
      request_timeout: 10_000,
      config: {
        command: "bun",
        args: [
          "spec/fixtures/typescript-mcp/index.ts",
          "--stdio"
        ],
        env: {
          "TEST_ENV" => "this_is_a_test"
        }
      }
    }
  },
  {
    name: "streamable-native",
    adapter: :ruby_llm,
    options: {
      name: "streamable-native-server",
      adapter: :ruby_llm,
      transport_type: :streamable,
      config: {
        url: TestServerManager::HTTP_SERVER_URL
      },
      request_timeout: 10_000
    }
  }
].freeze

mcp_sdk_clients = [
  {
    name: "streamable-mcp-sdk",
    adapter: :mcp_sdk,
    options: {
      name: "streamable-mcp-server",
      adapter: :mcp_sdk,
      transport_type: :streamable,
      config: {
        url: TestServerManager::HTTP_SERVER_URL
      },
      request_timeout: 10_000
    }
  },
  {
    name: "stdio-mcp-sdk",
    adapter: :mcp_sdk,
    options: {
      name: "stdio-mcp-sdk-server",
      adapter: :mcp_sdk,
      transport_type: :stdio,
      request_timeout: 10_000,
      config: {
        command: "bun",
        args: [
          "spec/fixtures/typescript-mcp/index.ts",
          "--stdio"
        ],
        env: {
          "TEST_ENV" => "this_is_a_test"
        }
      }
    }
  }
].freeze

CLIENT_OPTIONS = if RUBY_VERSION >= "3.1.0" && ClientRunner.mcp_sdk_available?
                   native_clients + mcp_sdk_clients
                 else
                   native_clients
                 end

PAGINATION_CLIENT_CONFIG = {
  name: "pagination",
  transport_type: :streamable,
  config: {
    url: TestServerManager::PAGINATION_SERVER_URL
  }
}.freeze

COMPLEX_FUNCTION_MODELS = [
  { provider: :anthropic, model: "claude-sonnet-4" },
  { provider: :gemini, model: "gemini-2.0-flash" },
  { provider: :openai, model: "gpt-4.1" }
].freeze

MCPTestConfiguration.configure!

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    TestServerManager.start_server
  end

  config.after(:suite) do
    TestServerManager.stop_server
  end
end
