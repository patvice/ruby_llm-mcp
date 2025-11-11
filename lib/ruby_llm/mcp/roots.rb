# frozen_string_literal: true

module RubyLLM
  module MCP
    class Roots
      attr_reader :paths

      def initialize(paths: [], adapter: nil)
        @paths = paths
        @adapter = adapter
      end

      def active?
        @paths.any?
      end

      def add(path)
        @paths << path
        @adapter.roots_list_change_notification
      end

      def remove(path)
        @paths.delete(path)
        @adapter.roots_list_change_notification
      end

      def to_request
        @paths.map do |path|
          name = File.basename(path, ".*")

          {
            uri: "file://#{path}",
            name: name
          }
        end
      end

      def to_h
        {
          paths: to_request
        }
      end
    end
  end
end
