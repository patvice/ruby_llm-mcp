# frozen_string_literal: true

module RubyLLM
  module MCP
    class Completion
      attr_reader :argument, :values, :total, :has_more

      def initialize(argument:, values:, total:, has_more:)
        @argument = argument
        @values = values
        @total = total
        @has_more = has_more
      end
    end
  end
end
