# frozen_string_literal: true

RubyLLM::MCP.configure do |config|
  config.log_level = Rails.env.production? ? Logger::WARN : Logger::INFO
  config.logger = Rails.logger
  config.config_path = Rails.root.join("config", "mcps.yml")
end
