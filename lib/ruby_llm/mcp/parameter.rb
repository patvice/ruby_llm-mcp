# frozen_string_literal: true

require "ruby_llm/tool"

module RubyLLM
  module MCP
    class Parameter < RubyLLM::Parameter
      attr_accessor :items, :properties, :enum, :union_type, :default, :title

      class << self
        def all_mcp_parameters?(parameters)
          parameters.is_a?(Hash) &&
            parameters.any? &&
            parameters.values.all? { |p| p.is_a?(RubyLLM::MCP::Parameter) }
        end
      end

      def initialize(name, type: "string", title: nil, desc: nil, required: true, default: nil, union_type: nil) # rubocop:disable Metrics/ParameterLists
        super(name, type: type.to_sym, desc: desc, required: required)
        @title = title
        @properties = {}
        @union_type = union_type
        @default = default
      end

      def item_type
        @items&.dig("type")&.to_sym
      end

      def as_json(*_args)
        to_h
      end

      def to_h
        {
          name: @name,
          type: @type,
          description: @desc,
          required: @required,
          default: @default,
          union_type: @union_type,
          items: @items&.to_h,
          properties: @properties&.values,
          enum: @enum
        }
      end
    end
  end
end
