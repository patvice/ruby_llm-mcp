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

          def build_properties(param) # rubocop:disable Metrics/MethodLength
            properties = case param.type
                         when :array
                           if param.try(:item_type) == :object
                             {
                               type: param_type_for_gemini(param.type),
                               title: param.try(:title),
                               description: param.description,
                               items: {
                                 type: param_type_for_gemini(param.try(:item_type)),
                                 properties: param.try(:properties).transform_values { |value| build_properties(value) }
                               }
                             }.compact
                           else
                             {
                               type: param_type_for_gemini(param.type),
                               title: param.try(:title),
                               description: param.description,
                               default: param.try(:default),
                               items: { type: param_type_for_gemini(param.try(:item_type)), enum: param.try(:enum) }.compact
                             }.compact
                           end
                         when :object
                           {
                             type: param_type_for_gemini(param.type),
                             title: param.try(:title),
                             description: param.description,
                             properties: param.try(:properties).transform_values { |value| build_properties(value) },
                             required: param.try(:properties).select { |_, p| p.required }.keys
                           }.compact
                         when :union
                           {
                             param.try(:union_type) => param.try(:properties).map { |prop| build_properties(prop) }
                           }
                         else
                           {
                             type: param_type_for_gemini(param.type),
                             title: param.try(:title),
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
