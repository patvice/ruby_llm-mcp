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
              properties: parameters.transform_values { |param| mcp_build_properties(param) },
              required: parameters.select { |_, p| p.required }.keys.map(&:to_s)
            }
          end

          def mcp_build_properties(param) # rubocop:disable Metrics/MethodLength
            properties = case param.type
                         when :array
                           if param.item_type == :object
                             {
                               type: param_type_for_gemini(param.type),
                               title: param.title,
                               description: param.description,
                               items: {
                                 type: param_type_for_gemini(param.item_type),
                                 properties: param.properties.transform_values { |value| mcp_build_properties(value) }
                               }
                             }.compact
                           else
                             {
                               type: param_type_for_gemini(param.type),
                               title: param.title,
                               description: param.description,
                               default: param.default,
                               items: { type: param_type_for_gemini(param.item_type), enum: param.enum }.compact
                             }.compact
                           end
                         when :object
                           {
                             type: param_type_for_gemini(param.type),
                             title: param.title,
                             description: param.description,
                             properties: param.properties.transform_values { |value| mcp_build_properties(value) },
                             required: param.properties.select { |_, p| p.required }.keys
                           }.compact
                         when :union
                           {
                             param.union_type => param.properties.map { |properties| mcp_build_properties(properties) }
                           }
                         else
                           {
                             type: param_type_for_gemini(param.type),
                             title: param.title,
                             description: param.description
                           }
                         end

            properties.compact
          end

          def param_type_for_gemini(type)
            RubyLLM::Providers::Gemini::Tools.param_type_for_gemini(type)
          end
        end
      end
    end
  end
end

module RubyLLM::Providers::Gemini::Tools
  alias original_format_parameters format_parameters
  module_function :original_format_parameters
  module_function :param_type_for_gemini

  def format_parameters(parameters)
    if RubyLLM::MCP::Parameter.all_mcp_parameters?(parameters)
      return RubyLLM::MCP::Providers::Gemini::ComplexParameterSupport.format_parameters(parameters)
    end

    original_format_parameters(parameters)
  end
  module_function :format_parameters
end
