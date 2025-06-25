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
    end

    class Tool < RubyLLM::Tool
      attr_reader :name, :description, :parameters, :coordinator, :tool_response

      def initialize(coordinator, tool_response)
        super()
        @coordinator = coordinator

        @name = tool_response["name"]
        @description = tool_response["description"].to_s
        @parameters = create_parameters(tool_response["inputSchema"])
        @annotations = tool_response["annotations"] ? Annotation.new(tool_response["annotations"]) : nil
      end

      def display_name
        "#{@coordinator.name}: #{@name}"
      end

      def execute(**params)
        result = @coordinator.execute_tool(
          name: @name,
          parameters: params
        )

        if result.error?
          error = result.to_error
          return { error: error.to_s }
        end

        text_values = result.value["content"].map { |content| content["text"] }.compact.join("\n")
        if result.execution_error?
          return { error: text_values }
        end

        if text_values.empty?
          create_content_for_message(result.value.dig("content", 0))
        else
          create_content_for_message({ "type" => "text", "text" => text_values })
        end
      end

      private

      def create_parameters(input_schema)
        params = {}
        return params if input_schema["properties"].nil?

        input_schema["properties"].each_key do |key|
          param_data = input_schema.dig("properties", key)

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
          union_type: union_type
        )

        param.properties = param_data[union_type].map do |value|
          process_parameter(key, value, lifted_type: param_data["type"])
        end.compact

        param
      end

      def process_parameter(key, param_data, lifted_type: nil)
        param = RubyLLM::MCP::Parameter.new(
          key,
          type: param_data["type"] || lifted_type,
          desc: param_data["description"],
          required: param_data["required"]
        )

        if param.type == :array
          items = param_data["items"]
          param.items = items
          if items.key?("properties")
            param.properties = create_parameters(items)
          end
          if param_data.key?("enum")
            param.enum = param_data["enum"]
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
            "content" => content["resource"]
          }

          resource = Resource.new(coordinator, resource_data)
          resource.to_content
        end
      end
    end
  end
end
