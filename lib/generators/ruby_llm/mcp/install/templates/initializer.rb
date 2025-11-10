# frozen_string_literal: true

# Configure RubyLLM MCP
RubyLLM::MCP.configure do |config|
  # Default SDK adapter to use (:ruby_llm or :mcp_sdk)
  # - :ruby_llm: Full-featured, supports all MCP features + extensions
  # - :mcp_sdk: Official SDK, limited features but maintained by Anthropic
  config.default_adapter = :ruby_llm

  # Request timeout in milliseconds
  config.request_timeout = 8000

  # Maximum connections in the pool
  config.max_connections = Float::INFINITY

  # Pool timeout in seconds
  config.pool_timeout = 5

  # Path to MCPs configuration file
  config.config_path = Rails.root.join("config", "mcps.yml")

  # Launch MCPs (:automatic, :manual)
  config.launch_control = :automatic

  # Configure roots for file system access (RubyLLM adapter only)
  # config.roots = [
  #   Rails.root.to_s
  # ]

  # Configure sampling (RubyLLM adapter only)
  config.sampling.enabled = false

  # Set preferred model for sampling
  # config.sampling.preferred_model do
  #   "claude-sonnet-4"
  # end

  # Set a guard for sampling
  # config.sampling.guard do
  #   Rails.env.development?
  # end

  # Event handlers (RubyLLM adapter only)
  # config.on_progress do |progress_token, progress, total|
  #   # Handle progress updates
  # end

  # config.on_human_in_the_loop do |tool_name, arguments|
  #   # Return true to allow, false to deny
  #   true
  # end

  # config.on_logging do |level, logger_name, data|
  #   # Handle logging from MCP servers
  # end
end
