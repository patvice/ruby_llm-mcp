# frozen_string_literal: true

module RubyLLM
  module MCP
    module Providers
      module Anthropic
        module ComplexParameterSupport
          module_function

          def clean_parameters(parameters)
            parameters.transform_values do |param|
              mcp_build_properties(param).compact
            end
          end

          def required_parameters(parameters)
            parameters.select { |_, param| param.required }.keys
          end

          def mcp_build_properties(param) # rubocop:disable Metrics/MethodLength
            case param.type
            when :array
              if param.item_type == :object
                {
                  type: param.type,
                  title: param.title,
                  description: param.description,
                  items: { type: param.item_type, properties: clean_parameters(param.properties) }
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
                properties: clean_parameters(param.properties),
                required: required_parameters(param.properties)
              }.compact
            when :union
              {
                param.union_type => param.properties.map { |property| mcp_build_properties(property) }
              }
            else
              {
                type: param.type,
                title: param.title,
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
  alias original_clean_parameters clean_parameters
  alias original_required_parameters required_parameters
  module_function :original_clean_parameters, :original_required_parameters

  def clean_parameters(parameters)
    if RubyLLM::MCP::Parameter.all_mcp_parameters?(parameters)
      return RubyLLM::MCP::Providers::Anthropic::ComplexParameterSupport.clean_parameters(parameters)
    end

    original_clean_parameters(parameters)
  end
  module_function :clean_parameters

  def required_parameters(parameters)
    if RubyLLM::MCP::Parameter.all_mcp_parameters?(parameters)
      return RubyLLM::MCP::Providers::Anthropic::ComplexParameterSupport.required_parameters(parameters)
    end

    original_required_parameters(parameters)
  end
  module_function :required_parameters
end
