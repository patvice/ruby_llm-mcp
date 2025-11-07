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
      attr_reader :name, :title, :description, :adapter, :tool_response, :with_prefix

      def initialize(adapter, tool_response, with_prefix: false)
        super()
        @adapter = adapter

        @with_prefix = with_prefix
        @name = format_name(tool_response["name"])
        @mcp_name = tool_response["name"]
        @description = tool_response["description"].to_s

        @input_schema = tool_response["inputSchema"]
        @output_schema = tool_response["outputSchema"]

        @annotations = tool_response["annotations"] ? Annotation.new(tool_response["annotations"]) : nil

        @normalized_input_schema = normalize_if_invalid(@input_schema)
      end

      def display_name
        "#{@adapter.client.name}: #{@name}"
      end

      def params_schema
        @normalized_input_schema
      end

      def execute(**params)
        result = @adapter.execute_tool(
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
          params_schema: @@normalized_input_schema,
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

          resource = Resource.new(adapter, resource_data)
          resource.to_content
        when "resource_link"
          resource_data = {
            "name" => content["name"],
            "uri" => content["uri"],
            "description" => content["description"],
            "mimeType" => content["mimeType"]
          }

          resource = Resource.new(adapter, resource_data)
          @adapter.register_resource(resource)
          resource.to_content
        end
      end

      def format_name(name)
        if @with_prefix
          "#{@adapter.client.name}_#{name}"
        else
          name
        end
      end

      def normalize_schema(schema)
        return schema if schema.nil?

        case schema
        when Hash
          normalize_hash_schema(schema)
        when Array
          normalize_array_schema(schema)
        else
          schema
        end
      end

      def normalize_hash_schema(schema)
        normalized = schema.transform_values { |value| normalize_schema_value(value) }
        ensure_object_properties(normalized)
        normalized
      end

      def normalize_array_schema(schema)
        schema.map { |item| normalize_schema_value(item) }
      end

      def normalize_schema_value(value)
        case value
        when Hash
          normalize_schema(value)
        when Array
          normalize_array_schema(value)
        else
          value
        end
      end

      def ensure_object_properties(schema)
        if schema["type"] == "object" && !schema.key?("properties")
          schema["properties"] = {}
        end
      end

      def normalize_if_invalid(schema)
        return schema if schema.nil?

        if valid_schema?(schema)
          schema
        else
          normalize_schema(schema)
        end
      end

      def valid_schema?(schema)
        return true if schema.nil?

        case schema
        when Hash
          valid_hash_schema?(schema)
        when Array
          schema.all? { |item| valid_schema?(item) }
        else
          true
        end
      end

      def valid_hash_schema?(schema)
        # Check if this level has missing properties for object type
        if schema["type"] == "object" && !schema.key?("properties")
          return false
        end

        # Recursively check nested schemas
        schema.each_value do |value|
          return false unless valid_schema?(value)
        end

        begin
          JSON::Validator.validate!(schema, {})
          true
        rescue JSON::Schema::SchemaError
          false
        rescue JSON::Schema::ValidationError
          true
        end
      end
    end
  end
end
