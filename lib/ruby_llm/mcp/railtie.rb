# frozen_string_literal: true

if defined?(Rails::Railtie)
  module RubyLLM
    module MCP
      class Railtie < Rails::Railtie
        generators do
          require_relative "../../generators/ruby_llm/mcp/install/install_generator"
          require_relative "../../generators/ruby_llm/mcp/oauth/install_generator"
        end
      end
    end
  end
end
