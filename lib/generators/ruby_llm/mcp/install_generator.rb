# frozen_string_literal: true

require "rails/generators/base"

module RubyLlm
  module Mcp
    module Generators
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        desc "Install RubyLLM MCP configuration files"

        def create_initializer
          template "initializer.rb", "config/initializers/ruby_llm_mcp.rb"
        end

        def create_config_file
          template "mcps.yml", "config/mcps.yml"
        end

        def display_readme
          return unless behavior == :invoke

          say "✅ RubyLLM MCP installed!", :green
          say ""
          say "Next steps:", :blue
          say "  1. Configure config/initializers/ruby_llm_mcp.rb (main settings)"
          say "  2. Define servers in config/mcps.yml"
          say "  3. Install MCP servers (e.g., npm install @modelcontextprotocol/server-filesystem)"
          say "  4. Set environment variables for authentication"
          say ""
          say "📚 Full docs: https://www.rubyllm-mcp.com/", :cyan
          say ""
          say "⭐ Help us improve!", :magenta
          say "  Report issues or show your support with a GitHub star: https://github.com/patvice/ruby_llm-mcp"
        end
      end
    end
  end
end
