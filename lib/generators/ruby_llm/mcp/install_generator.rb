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
          readme "README.txt" if behavior == :invoke
        end
      end
    end
  end
end
