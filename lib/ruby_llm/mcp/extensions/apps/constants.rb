# frozen_string_literal: true

module RubyLLM
  module MCP
    module Extensions
      module Apps
        module Constants
          META_KEY = "_meta"

          UI_KEY = "ui"
          RESOURCE_URI_KEY = "resourceUri"
          LEGACY_RESOURCE_URI_KEY = "ui/resourceUri"
          VISIBILITY_KEY = "visibility"
          MIME_TYPES_KEY = "mimeTypes"
          APP_HTML_MIME_TYPE = "text/html;profile=mcp-app"

          CSP_KEY = "csp"
          PERMISSIONS_KEY = "permissions"
          DOMAIN_KEY = "domain"
          PREFERS_BORDER_KEY = "prefersBorder"
          PREFERS_BORDER_ALT_KEY = "prefers_border"

          DEFAULT_VISIBILITY = %w[model app].freeze
        end
      end
    end
  end
end
