# frozen_string_literal: true

module RubyLLM
  module MCP
    module Protocol
      module_function

      LATEST_PROTOCOL_VERSION = "2025-06-18"
      DEFAULT_NEGOTIATED_PROTOCOL_VERSION = "2025-03-26"
      SUPPORTED_PROTOCOL_VERSIONS = [
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

      def default_negotiated_version
        DEFAULT_NEGOTIATED_PROTOCOL_VERSION
      end
    end
  end
end
