# frozen_string_literal: true

module RubyLLM
  module MCP
    module Extensions
      module Apps
        class ToolMetadata
          attr_reader :resource_uri, :visibility, :raw

          def initialize(raw)
            @raw = raw.is_a?(Hash) ? raw : {}

            ui_meta = @raw[Constants::UI_KEY]
            @resource_uri = ui_meta&.dig(Constants::RESOURCE_URI_KEY) || @raw[Constants::LEGACY_RESOURCE_URI_KEY]

            @visibility = normalize_visibility(ui_meta&.dig(Constants::VISIBILITY_KEY))
          end

          def model_visible?
            @visibility.include?("model")
          end

          def app_visible?
            @visibility.include?("app")
          end

          private

          def normalize_visibility(value)
            normalized = case value
                         when nil
                           Constants::DEFAULT_VISIBILITY
                         when Array
                           value
                         else
                           [value]
                         end

            normalized.map(&:to_s)
          end
        end
      end
    end
  end
end
