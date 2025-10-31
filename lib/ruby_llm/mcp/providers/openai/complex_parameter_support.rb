# frozen_string_literal: true

module RubyLLM
  module MCP
    module Providers
      module OpenAI
        module ComplexParameterSupport
          module_function

          def param_schema(param) # rubocop:disable Metrics/MethodLength
            properties = case param.type
                         when :array
                           if param.try(:item_type) == :object
                             {
                               type: param.type,
                               title: param.try(:title),
                               description: param.description,
                               items: {
                                 type: param.try(:item_type),
                                 properties: param.try(:properties).transform_values { |value| param_schema(value) }
                               }
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
                             properties: param.try(:properties).transform_values { |value| param_schema(value) },
                             required: param.try(:properties).select { |_, p| p.required }.keys
                           }.compact
                         when :union
                           {
                             param.try(:union_type) => param.try(:properties).map { |property| param_schema(property) }
                           }
                         else
                           {
                             type: param.type,
                             title: param.try(:title),
                             description: param.description
                           }.compact
                         end

            properties.compact
          end
        end
      end
    end
  end
end

RubyLLM::Providers::OpenAI.extend(RubyLLM::MCP::Providers::OpenAI::ComplexParameterSupport)
