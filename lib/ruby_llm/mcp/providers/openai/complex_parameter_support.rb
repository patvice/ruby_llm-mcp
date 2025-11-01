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
                           if param.item_type == :object
                             {
                               type: param.type,
                               title: param.title,
                               description: param.description,
                               items: {
                                 type: param.item_type,
                                 properties: param.properties.transform_values { |value| param_schema(value) }
                               }
                             }.compact
                           else
                             {
                               type: param.type,
                               title: param.title,
                               description: param.description,
                               default: param.default,
                               items: { type: param.item_type, enum: param.enum }.compact
                             }.compact
                           end
                         when :object
                           {
                             type: param.type,
                             title: param.title,
                             description: param.description,
                             properties: param.properties.transform_values { |value| param_schema(value) },
                             required: param.properties.select { |_, p| p.required }.keys
                           }.compact
                         when :union
                           {
                             param.union_type => param.properties.map { |property| param_schema(property) }
                           }
                         else
                           {
                             type: param.type,
                             title: param.title,
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

module RubyLLM::Providers::OpenAI::Tools
  alias original_param_schema param_schema
  module_function :original_param_schema

  def param_schema(param)
    if param.is_a?(RubyLLM::MCP::Parameter)
      return RubyLLM::MCP::Providers::OpenAI::ComplexParameterSupport.param_schema(param)
    end

    original_param_schema(param)
  end
  module_function :param_schema
end
