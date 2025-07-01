# frozen_string_literal: true

module RubyLLM
  module MCP
    module Providers
      module OpenAI
        module ComplexParameterSupport
          module_function

          def param_schema(param)
            properties = case param.type
                         when :array
                           if param.item_type == :object
                             {
                               type: param.type,
                               items: {
                                 type: param.item_type,
                                 properties: param.properties.transform_values { |value| param_schema(value) }
                               }
                             }
                           else
                             {
                               type: param.type,
                               default: param.default,
                               items: { type: param.item_type, enum: param.enum }.compact
                             }.compact
                           end
                         when :object
                           {
                             type: param.type,
                             properties: param.properties.transform_values { |value| param_schema(value) },
                             required: param.properties.select { |_, p| p.required }.keys
                           }
                         when :union
                           {
                             param.union_type => param.properties.map { |property| param_schema(property) }
                           }
                         else
                           {
                             type: param.type,
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
