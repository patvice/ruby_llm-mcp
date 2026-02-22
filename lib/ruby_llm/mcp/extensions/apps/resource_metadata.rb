# frozen_string_literal: true

module RubyLLM
  module MCP
    module Extensions
      module Apps
        class ResourceMetadata
          attr_reader :csp, :permissions, :domain, :prefers_border, :raw

          def initialize(raw)
            @raw = raw.is_a?(Hash) ? raw : {}

            ui_meta = @raw[Constants::UI_KEY]
            @csp = ui_meta&.dig(Constants::CSP_KEY)
            @permissions = ui_meta&.dig(Constants::PERMISSIONS_KEY)
            @domain = ui_meta&.dig(Constants::DOMAIN_KEY)
            @prefers_border = ui_meta&.dig(Constants::PREFERS_BORDER_KEY)
            @prefers_border = ui_meta&.dig(Constants::PREFERS_BORDER_ALT_KEY) if @prefers_border.nil?
          end
        end
      end
    end
  end
end
