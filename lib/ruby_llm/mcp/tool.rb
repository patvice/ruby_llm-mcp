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
      attr_reader :name, :title, :description, :coordinator, :tool_response, :with_prefix

      def initialize(coordinator, tool_response, with_prefix: false)
        super()
        @coordinator = coordinator

        @with_prefix = with_prefix
        @name = format_name(tool_response["name"])
        @mcp_name = tool_response["name"]
        @description = tool_response["description"].to_s

        @input_schema = tool_response["inputSchema"]
        @output_schema = tool_response["outputSchema"]

        @annotations = tool_response["annotations"] ? Annotation.new(tool_response["annotations"]) : nil
      end

      def display_name
        "#{@coordinator.name}: #{@name}"
      end

      def params_schema
        @input_schema
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
          params_schema: @input_schema,
          annotations: @annotations&.to_h
        }
      end

      alias to_json to_h

      private

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
    end
  end
end
