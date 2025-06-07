# frozen_string_literal: true

module RubyLLM
  module MCP
    class Resource
      attr_reader :uri, :name, :description, :mime_type, :mcp_client, :template

      def initialize(mcp_client, resource, template: false)
        @mcp_client = mcp_client
        @uri = resource["uri"]
        @name = resource["name"]
        @description = resource["description"]
        @mime_type = resource["mimeType"]
        @template = template
      end

      def content(parsable_information: {})
        response = if template?
                     templated_uri = apply_template(@uri, parsable_information)

                     read_response(uri: templated_uri)
                   else
                     read_response
                   end

        response.dig("result", "contents", 0, "text") ||
          response.dig("result", "contents", 0, "blob")
      end

      def template?
        @template
      end

      private

      def read_response(uri: @uri)
        parsed = URI.parse(uri)
        case parsed.scheme
        when "http", "https"
          fetch_uri_content(uri)
        else # file:// or git://
          @read_response ||= @mcp_client.resource_read_request(uri: uri)
        end
      end

      def fetch_uri_content(uri)
        response = Faraday.get(uri)
        { "result" => { "contents" => [{ "text" => response.body }] } }
      end

      def apply_template(uri, parsable_information)
        uri.gsub(/\{(\w+)\}/) do
          parsable_information[::Regexp.last_match(1).to_sym] || "{#{::Regexp.last_match(1)}}"
        end
      end
    end
  end
end
