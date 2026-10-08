# frozen_string_literal: true

require "base64"
require "stringio"

module RubyLLM
  module MCP
    class Attachment < RubyLLM::Attachment
      def initialize(content, mime_type)
        @encoded_content = content
        extension = mime_type.to_s.split("/").last
        super(StringIO.new(Base64.strict_decode64(content)), filename: "mcp-result.#{extension}")
        @mime_type = mime_type
      end

      def encoded
        @encoded_content
      end
    end
  end
end
