# frozen_string_literal: true

module RubyLLM
  module MCP
    module Extensions
      module Constants
        UI_EXTENSION_ID = "io.modelcontextprotocol/ui"
        APPS_EXTENSION_ALIAS = "io.modelcontextprotocol/apps"

        EXTENSION_ALIASES = {
          APPS_EXTENSION_ALIAS => UI_EXTENSION_ID
        }.freeze
      end
    end
  end
end
