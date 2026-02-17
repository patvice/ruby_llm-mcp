# frozen_string_literal: true

require "json_schemer"

module RubyLLM
  module MCP
    module SchemaValidator
      module_function

      def valid?(schema, data)
        return true if schema.nil?

        schemer(schema).valid?(data)
      rescue StandardError
        false
      end

      def valid_schema?(schema)
        return true if schema.nil?

        schemer(schema)
        true
      rescue StandardError
        false
      end

      def schemer(schema)
        JSONSchemer.schema(schema)
      end
      private_class_method :schemer
    end
  end
end
