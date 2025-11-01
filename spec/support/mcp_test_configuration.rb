# frozen_string_literal: true

module MCPTestConfiguration
  module_function

  class NullLogger
    def debug(*); end
    def info(*); end
    def warn(*); end
    def error(*); end
    def fatal(*); end
    def unknown(*); end
  end

  def configure_ruby_llm!
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch("OPENAI_API_KEY", "test")
      config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", "test")
      config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", "test")
      config.deepseek_api_key = ENV.fetch("DEEPSEEK_API_KEY", "test")
      config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", "test")

      config.bedrock_api_key = ENV.fetch("AWS_ACCESS_KEY_ID", "test")
      config.bedrock_secret_key = ENV.fetch("AWS_SECRET_ACCESS_KEY", "test")
      config.bedrock_region = ENV.fetch("AWS_REGION", "us-west-2")
      config.bedrock_session_token = ENV.fetch("AWS_SESSION_TOKEN", nil)

      config.request_timeout = 240
      config.max_retries = 10
      config.retry_interval = 1
      config.retry_backoff_factor = 3
      config.retry_interval_randomness = 0.5
    end
  end

  def configure!
    RubyLLM::MCP.configure do |config|
      if ENV["RUBY_LLM_DEBUG"]
        config.log_level = :debug
      else
        config.logger = NullLogger.new
      end
    end
  end

  def reset_config!
    RubyLLM::MCP.config.reset!
    configure!
  end
end
