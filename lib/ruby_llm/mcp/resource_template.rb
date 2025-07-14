# frozen_string_literal: true

require "httpx"

module RubyLLM
  module MCP
    class ResourceTemplate
      attr_reader :uri, :name, :description, :mime_type, :coordinator, :template

      def initialize(coordinator, resource)
        @coordinator = coordinator
        @uri = resource["uriTemplate"]
        @name = resource["name"]
        @description = resource["description"]
        @mime_type = resource["mimeType"]
      end

      def fetch_resource(arguments: {})
        uri = apply_template(@uri, arguments)
        result = read_response(uri)
        content_response = result.value.dig("contents", 0)

        Resource.new(coordinator, {
                       "uri" => uri,
                       "name" => "#{@name} (#{uri})",
                       "description" => @description,
                       "mimeType" => @mime_type,
                       "content_response" => content_response
                     })
      end

      def to_content(arguments: {})
        fetch_resource(arguments: arguments).to_content
      end

      def complete(argument, value, context: nil)
        if @coordinator.capabilities.completion?
          result = @coordinator.completion_resource(uri: @uri, argument: argument, value: value, context: context)
          result.raise_error! if result.error?

          response = result.value["completion"]

          Completion.new(argument: argument, values: response["values"], total: response["total"],
                         has_more: response["hasMore"])
        else
          message = "Completion is not available for this MCP server"
          raise Errors::Capabilities::CompletionNotAvailable.new(message: message)
        end
      end

      private

      def content_type
        if @content.key?("type")
          @content["type"]
        else
          "text"
        end
      end

      def read_response(uri)
        parsed = URI.parse(uri)
        case parsed.scheme
        when "http", "https"
          fetch_uri_content(uri)
        else # file:// or git://
          @coordinator.resource_read(uri: uri)
        end
      end

      def fetch_uri_content(uri)
        response = HTTPX.get(uri)
        { "result" => { "contents" => [{ "text" => response.body }] } }
      end

      def apply_template(uri, arguments)
        uri.gsub(/\{(\w+)\}/) do
          arguments[::Regexp.last_match(1).to_s] ||
            arguments[::Regexp.last_match(1).to_sym] ||
            "{#{::Regexp.last_match(1)}}"
        end
      end
    end
  end
end
