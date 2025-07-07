# frozen_string_literal: true

require "httpx"

module RubyLLM
  module MCP
    class Resource
      attr_reader :uri, :name, :description, :mime_type, :coordinator, :subscribed

      def initialize(coordinator, resource)
        @coordinator = coordinator
        @uri = resource["uri"]
        @name = resource["name"]
        @description = resource["description"]
        @mime_type = resource["mimeType"]
        if resource.key?("content_response")
          @content_response = resource["content_response"]
          @content = @content_response["text"] || @content_response["blob"]
        end

        @subscribed = false
      end

      def content
        return @content unless @content.nil?

        result = read_response
        result.raise_error! if result.error?

        @content_response = result.value.dig("contents", 0)
        @content = @content_response["text"] || @content_response["blob"]
      end

      def content_loaded?
        !@content.nil?
      end

      def subscribe!
        if @coordinator.capabilities.resource_subscribe?
          @coordinator.resources_subscribe(uri: @uri)
          @subscribed = true
        else
          message = "Resource subscribe is not available for this MCP server"
          raise Errors::Capabilities::ResourceSubscribeNotAvailable.new(message: message)
        end
      end

      def reset_content!
        @content = nil
        @content_response = nil
      end

      def include(chat, **args)
        message = Message.new(
          role: "user",
          content: to_content(**args)
        )

        chat.add_message(message)
      end

      def to_content
        content = self.content

        case content_type
        when "text"
          MCP::Content.new(text: "#{name}: #{description}\n\n#{content}")
        when "blob"
          attachment = MCP::Attachment.new(content, mime_type)
          MCP::Content.new(text: "#{name}: #{description}", attachments: [attachment])
        end
      end

      def to_h
        {
          uri: @uri,
          name: @name,
          description: @description,
          mime_type: @mime_type,
          contented_loaded: content_loaded?,
          content: @content
        }
      end

      alias to_json to_h

      private

      def content_type
        return "text" if @content_response.nil?

        if @content_response.key?("blob")
          "blob"
        else
          "text"
        end
      end

      def read_response(uri: @uri)
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
    end
  end
end
