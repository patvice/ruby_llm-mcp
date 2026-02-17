# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Protocol
        module_function

        LATEST_PROTOCOL_VERSION = "2025-06-18"
        DRAFT_PROTOCOL_VERSION = "2026-01-26"
        DEFAULT_NEGOTIATED_PROTOCOL_VERSION = "2025-03-26"
        SUPPORTED_PROTOCOL_VERSIONS = [
          DRAFT_PROTOCOL_VERSION,
          LATEST_PROTOCOL_VERSION,
          "2025-03-26",
          "2024-11-05",
          "2024-10-07"
        ].freeze

        def supported_version?(version)
          SUPPORTED_PROTOCOL_VERSIONS.include?(version)
        end

        def supported_versions
          SUPPORTED_PROTOCOL_VERSIONS
        end

        def latest_version
          LATEST_PROTOCOL_VERSION
        end

        def draft_version
          DRAFT_PROTOCOL_VERSION
        end

        def default_negotiated_version
          DEFAULT_NEGOTIATED_PROTOCOL_VERSION
        end

        def date_version?(value)
          return false unless value.is_a?(String)

          /\A\d{4}-\d{2}-\d{2}\z/.match?(value)
        end

        def compare_date_versions(version_a, version_b)
          return nil unless date_version?(version_a) && date_version?(version_b)

          Date.iso8601(version_a) <=> Date.iso8601(version_b)
        rescue Date::Error
          nil
        end

        def draft_or_newer?(version)
          return false if version.nil?

          normalized = version.to_s
          return true if normalized.start_with?("DRAFT-")

          comparison = compare_date_versions(normalized, DRAFT_PROTOCOL_VERSION)
          !comparison.nil? && comparison >= 0
        end

        # Extensions are part of the stable protocol track from 2025-06-18 onward.
        def extensions_supported?(version)
          return false if version.nil?

          normalized = version.to_s
          return true if normalized.start_with?("DRAFT-")

          comparison = compare_date_versions(normalized, LATEST_PROTOCOL_VERSION)
          !comparison.nil? && comparison >= 0
        end
      end
    end
  end
end
