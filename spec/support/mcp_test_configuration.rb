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

  def configure!
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
      config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
      config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
    end

    RubyLLM::MCP.configure do |config|
      if ENV["RUBY_LLM_DEBUG"]
        config.log_level = :debug
      else
        config.logger = NullLogger.new
      end
      config.support_complex_parameters!
    end
  end

  def reset_config!
    RubyLLM::MCP.config.reset!
    configure!
  end
end
