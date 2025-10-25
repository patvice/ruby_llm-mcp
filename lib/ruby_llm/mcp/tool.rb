# frozen_string_literal: true

module RubyLLM
  module MCP
    class Annotation
      attr_reader :title, :read_only_hint, :destructive_hint, :idempotent_hint, :open_world_hint

      def initialize(annotation)
        @title = annotation["title"] || ""
        @read_only_hint = annotation["readOnlyHint"] || false
        @destructive_hint = annotation["destructiveHint"] || true
        @idempotent_hint = annotation["idempotentHint"] || false
        @open_world_hint = annotation["openWorldHint"] || true
      end

      def to_h
        {
          title: @title,
          readOnlyHint: @read_only_hint,
          destructiveHint: @destructive_hint,
          idempotentHint: @idempotent_hint,
          openWorldHint: @open_world_hint
        }
      end
    end

    class Tool < RubyLLM::Tool
      attr_reader :name, :title, :description, :parameters, :coordinator, :tool_response, :with_prefix

      def initialize(coordinator, tool_response, with_prefix: false)
        super()
        @coordinator = coordinator

        @with_prefix = with_prefix
        @name = format_name(tool_response["name"])
        @mcp_name = tool_response["name"]
        @description = tool_response["description"].to_s
        @parameters = create_parameters(tool_response["inputSchema"])

        @input_schema = tool_response["inputSchema"]
        @output_schema = tool_response["outputSchema"]

        @annotations = tool_response["annotations"] ? Annotation.new(tool_response["annotations"]) : nil
      end

      def display_name
        "#{@coordinator.name}: #{@name}"
      end

      def execute(**params)
        result = @coordinator.execute_tool(
          name: @mcp_name,
          parameters: params
        )

        if result.error?
          error = result.to_error
          return { error: error.to_s }
        end

        text_values = result.value["content"].map { |content| content["text"] }.compact.join("\n")
        if result.execution_error?
          return { error: "Tool execution error: #{text_values}" }
        end

        if result.value.key?("structuredContent") && !@output_schema.nil?
          is_valid = JSON::Validator.validate(@output_schema, result.value["structuredContent"])
          unless is_valid
            return { error: "Structued outputs was not invalid: #{result.value['structuredContent']}" }
          end

          return text_values
        end

        if text_values.empty?
          create_content_for_message(result.value.dig("content", 0))
        else
          create_content_for_message({ "type" => "text", "text" => text_values })
        end
      end

      def to_h
        {
          name: @name,
          description: @description,
          parameters: @parameters.to_h,
          annotations: @annotations&.to_h
        }
      end

      alias to_json to_h

      private

      def create_parameters(schema)
        params = {}
        return params if schema["properties"].nil?

        schema["properties"].each_key do |key|
          param_data = schema.dig("properties", key)
          param_data = expand_shorthand_type_to_anyof(param_data)

          param = if param_data.key?("oneOf") || param_data.key?("anyOf") || param_data.key?("allOf")
                    process_union_parameter(key, param_data)
                  else
                    process_parameter(key, param_data)
                  end

          params[key] = param
        end

        params
      end

      def process_union_parameter(key, param_data)
        union_type = param_data.keys.first
        param = RubyLLM::MCP::Parameter.new(
          key,
          type: :union,
          title: param_data["title"],
          desc: param_data["description"],
          union_type: union_type
        )

        param.properties = param_data[union_type].map do |value|
          expanded_value = expand_shorthand_type_to_anyof(value)
          if expanded_value.key?("anyOf")
            process_union_parameter(key, expanded_value)
          else
            process_parameter(key, value, lifted_type: param_data["type"])
          end
        end.compact

        param
      end

      def process_parameter(key, param_data, lifted_type: nil)
        param = RubyLLM::MCP::Parameter.new(
          key,
          type: param_data["type"] || lifted_type || "string",
          title: param_data["title"],
          desc: param_data["description"],
          required: param_data["required"],
          default: param_data["default"]
        )

        if param.type == :array
          items = param_data["items"]
          param.items = items
          if items.key?("properties")
            param.properties = create_parameters(items)
          end
          if items.key?("enum")
            param.enum = items["enum"]
          end
        elsif param.type == :object
          if param_data.key?("properties")
            param.properties = create_parameters(param_data)
          end
        end

        param
      end

      def create_content_for_message(content)
        case content["type"]
        when "text"
          MCP::Content.new(text: content["text"])
        when "image", "audio"
          attachment = MCP::Attachment.new(content["data"], content["mimeType"])
          MCP::Content.new(text: nil, attachments: [attachment])
        when "resource"
          resource_data = {
            "name" => name,
            "description" => description,
            "uri" => content.dig("resource", "uri"),
            "mimeType" => content.dig("resource", "mimeType"),
            "content_response" => {
              "text" => content.dig("resource", "text"),
              "blob" => content.dig("resource", "blob")
            }
          }

          resource = Resource.new(coordinator, resource_data)
          resource.to_content
        when "resource_link"
          resource_data = {
            "name" => content["name"],
            "uri" => content["uri"],
            "description" => content["description"],
            "mimeType" => content["mimeType"]
          }

          resource = Resource.new(coordinator, resource_data)
          @coordinator.register_resource(resource)
          resource.to_content
        end
      end

      def format_name(name)
        if @with_prefix
          "#{@coordinator.name}_#{name}"
        else
          name
        end
      end

      # Expands shorthand type arrays into explicit anyOf unions
      # Converts { "type": ["string", "number"] } into { "anyOf": [{"type": "string"}, {"type": "number"}] }
      # This keeps $ref references clean and provides a consistent structure for union types
      #
      # @param param_data [Hash] The parameter data that may contain a shorthand type array
      # @return [Hash] The expanded parameter data with anyOf, or the original if not a shorthand
      def expand_shorthand_type_to_anyof(param_data)
        type = param_data["type"]
        return param_data unless type.is_a?(Array)

        {
          "anyOf" => type.map { |t| { "type" => t } }
        }.merge(param_data.except("type"))
      end
    end
  end
end
