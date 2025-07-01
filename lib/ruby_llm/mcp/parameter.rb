# frozen_string_literal: true

require "ruby_llm/tool"

module RubyLLM
  module MCP
    class Parameter < RubyLLM::Parameter
      attr_accessor :items, :properties, :enum, :union_type, :default

      def initialize(name, type: "string", desc: nil, required: true, default: nil, union_type: nil) # rubocop:disable Metrics/ParameterLists
        super(name, type: type.to_sym, desc: desc, required: required)
        @properties = {}
        @union_type = union_type
        @default = default
      end

      def item_type
        @items["type"].to_sym
      end
    end
  end
end
