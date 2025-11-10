# frozen_string_literal: true

require "rbconfig"

module RubyLLM
  module MCP
    module Auth
      module Browser
        # Browser opening utilities for different operating systems
        # Handles cross-platform browser launching
        class Opener
          attr_reader :logger

          def initialize(logger: nil)
            @logger = logger || MCP.logger
          end

          # Open browser to URL
          # @param url [String] URL to open
          # @return [Boolean] true if successful
          def open_browser(url)
            case RbConfig::CONFIG["host_os"]
            when /darwin/
              system("open", url)
            when /linux|bsd/
              system("xdg-open", url)
            when /mswin|mingw|cygwin/
              system("start", url)
            else
              @logger.warn("Unknown operating system, cannot open browser automatically")
              false
            end
          rescue StandardError => e
            @logger.warn("Failed to open browser: #{e.message}")
            false
          end
        end
      end
    end
  end
end
