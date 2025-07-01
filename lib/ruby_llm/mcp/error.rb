# frozen_string_literal: true

module RubyLLM
  module MCP
    class Error
      def initialize(error_data)
        @code = error_data["code"]
        @message = error_data["message"]
        @data = error_data["data"]
      end

      def type
        case @code
        when -32_700
          :parse_error
        when -32_600
          :invalid_request
        when -32_601
          :method_not_found
        when -32_602
          :invalid_params
        when -32_603
          :internal_error
        else
          :custom_error
        end
      end

      def to_s
        "Error: code: #{@code} (#{type}), message: #{@message}, data: #{@data}"
      end
    end
  end
end
