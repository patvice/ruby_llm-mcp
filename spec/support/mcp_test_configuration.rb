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
    RubyLLM::MCP.configure do |config|
      config.logger = NullLogger.new
      config.support_complex_parameters!
    end
  end
end
