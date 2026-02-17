# frozen_string_literal: true

module RubyLLM
  module MCP
    module Extensions
      class Configuration
        def initialize
          reset!
        end

        def register(id, config = {})
          canonical_id = Registry.canonicalize_id(id)
          if canonical_id.nil?
            raise ArgumentError, "Extension id is required"
          end

          unless config.nil? || config.is_a?(Hash)
            raise ArgumentError, "Extension config for '#{canonical_id}' must be a Hash"
          end

          @extensions = Registry.merge(@extensions, { canonical_id => config })
          self
        end

        def enable_apps(config = {})
          normalized = Registry.deep_stringify_keys(config || {})
          validate_apps_config!(normalized)
          normalized[Apps::Constants::MIME_TYPES_KEY] ||= [Apps::Constants::APP_HTML_MIME_TYPE]

          register(Constants::UI_EXTENSION_ID, normalized)
        end

        def to_h
          Registry.normalize_map(@extensions)
        end

        def empty?
          to_h.empty?
        end

        def reset!
          @extensions = {}
          self
        end

        private

        def validate_apps_config!(config)
          misplaced_keys = [
            Apps::Constants::UI_KEY,
            Apps::Constants::RESOURCE_URI_KEY,
            Apps::Constants::LEGACY_RESOURCE_URI_KEY,
            Apps::Constants::VISIBILITY_KEY
          ]

          if misplaced_keys.any? { |key| config.key?(key) }
            raise ArgumentError,
                  "MCP Apps extension config uses client capability fields (for example, 'mimeTypes'); " \
                  "tool metadata fields like 'resourceUri' and 'visibility' belong in tool _meta.ui"
          end

          mime_types = config[Apps::Constants::MIME_TYPES_KEY]
          return if mime_types.nil?

          unless mime_types.is_a?(Array) && mime_types.all? { |value| value.is_a?(String) && !value.empty? }
            raise ArgumentError, "'mimeTypes' must be an array of non-empty strings"
          end
        end
      end
    end
  end
end
