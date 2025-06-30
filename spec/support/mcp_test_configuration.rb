# frozen_string_literal: true

module MCPTestConfiguration
  module_function

  def configure!
    RubyLLM::MCP.configure do |config|
      config.log_file = $stdout
      config.log_level = Logger::ERROR
      config.support_complex_parameters!
    end
  end
end
