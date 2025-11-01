# frozen_string_literal: true

# Configure RubyLLM MCP
RubyLLM::MCP.configure do |config|
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

  # Configure roots for file system access
  # config.roots = [
  #   Rails.root.to_s
  # ]

  # Configure sampling (optional)
  config.sampling.enabled = false

  # Set preferred model for sampling
  # config.sampling.preferred_model do
  #   # Return the preferred model name
  #   "claude-sonnet-4"
  # end

  # Set a guard for sampling
  # config.sampling.guard do
  #   # Return true to enable sampling, false to disable
  #   Rails.env.development?
  # end
end
