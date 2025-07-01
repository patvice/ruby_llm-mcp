# frozen_string_literal: true

module RubyLLM
  module MCP
    module Providers
      module Gemini
        module ComplexParameterSupport
          module_function

          # Format tool parameters for Gemini API
          def format_parameters(parameters)
            {
              type: "OBJECT",
              properties: parameters.transform_values { |param| build_properties(param) },
              required: parameters.select { |_, p| p.required }.keys.map(&:to_s)
            }
          end

          def build_properties(param)
            properties = case param.type
                         when :array
                           if param.item_type == :object
                             {
                               type: param_type_for_gemini(param.type),
                               items: {
                                 type: param_type_for_gemini(param.item_type),
                                 properties: param.properties.transform_values { |value| build_properties(value) }
                               }
                             }
                           else
                             {
                               type: param_type_for_gemini(param.type),
                               default: param.default,
                               items: { type: param_type_for_gemini(param.item_type), enum: param.enum }.compact
                             }.compact
                           end
                         when :object
                           {
                             type: param_type_for_gemini(param.type),
                             properties: param.properties.transform_values { |value| build_properties(value) },
                             required: param.properties.select { |_, p| p.required }.keys
                           }
                         when :union
                           {
                             param.union_type => param.properties.map { |properties| build_properties(properties) }
                           }
                         else
                           {
                             type: param_type_for_gemini(param.type),
                             description: param.description
                           }
                         end

            properties.compact
          end
        end
      end
    end
  end
end

RubyLLM::Providers::Gemini.extend(RubyLLM::MCP::Providers::Gemini::ComplexParameterSupport)
