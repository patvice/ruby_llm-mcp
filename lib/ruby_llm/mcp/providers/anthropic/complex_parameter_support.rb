# frozen_string_literal: true

module RubyLLM
  module MCP
    module Providers
      module Anthropic
        module ComplexParameterSupport
          module_function

          def clean_parameters(parameters)
            parameters.transform_values do |param|
              build_properties(param).compact
            end
          end

          def required_parameters(parameters)
            parameters.select { |_, param| param.required }.keys
          end

          def build_properties(param) # rubocop:disable Metrics/MethodLength
            case param.type
            when :array
              if param.try(:item_type) == :object
                {
                  type: param.type,
                  title: param.try(:title),
                  description: param.description,
                  items: { type: param.try(:item_type), properties: clean_parameters(param.try(:properties)) }
                }.compact
              else
                {
                  type: param.type,
                  title: param.try(:title),
                  description: param.description,
                  default: param.try(:default),
                  items: { type: param.try(:item_type), enum: param.try(:enum) }.compact
                }.compact
              end
            when :object
              {
                type: param.type,
                title: param.try(:title),
                description: param.description,
                properties: clean_parameters(param.try(:properties)),
                required: required_parameters(param.try(:properties))
              }.compact
            when :union
              {
                param.try(:union_type) => param.try(:properties).map { |property| build_properties(property) }
              }
            else
              {
                type: param.type,
                title: param.try(:title),
                description: param.description
              }.compact
            end
          end
        end
      end
    end
  end
end

module RubyLLM::Providers::Anthropic::Tools
  def self.clean_parameters(parameters)
    RubyLLM::MCP::Providers::Anthropic::ComplexParameterSupport.clean_parameters(parameters)
  end

  def self.required_parameters(parameters)
    RubyLLM::MCP::Providers::Anthropic::ComplexParameterSupport.required_parameters(parameters)
  end
end
