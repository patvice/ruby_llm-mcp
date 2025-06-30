# frozen_string_literal: true

require "ruby_llm/tool"

module RubyLLM
  module MCP
    class Parameter < RubyLLM::Parameter
      attr_accessor :items, :properties, :enum, :union_type

      def initialize(name, type: "string", desc: nil, required: true, union_type: nil)
        super(name, type: type.to_sym, desc: desc, required: required)
        @properties = {}
        @union_type = union_type
      end

      def item_type
        @items["type"].to_sym
      end
    end
  end
end
