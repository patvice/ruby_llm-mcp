# frozen_string_literal: true

module RubyLLM
  module MCP
    class Railtie < Rails::Railtie
      config.after_initialize do
        if RubyLLM::MCP.config.launch_control == :automatic
          RubyLLM::MCP.clients.map(&:start)
          at_exit do
            RubyLLM::MCP.clients.map(&:stop)
          end
        end
      end

      generators do
        require_relative "../../generators/ruby_llm/mcp/install_generator"
      end
    end
  end
end
