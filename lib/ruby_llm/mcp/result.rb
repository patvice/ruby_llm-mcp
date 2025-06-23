# frozen_string_literal: true

module RubyLLM
  module MCP
    class Notification
      attr_reader :type, :params

      def initialize(response)
        @type = response["type"]
        @params = response["params"]
      end
    end

    class Result
      attr_reader :result, :error, :params, :id, :next_cursor

      def initialize(response, progress_handler:)
        @response = response
        @id = response["id"]
        @result = response["result"]
        @params = response["params"]
        @method = response["method"]
        @error = response["error"] || {}
        @progress_handler = progress_handler

        @result_is_error = response.dig("result", "isError") || false
        @next_cursor = response.dig("result", "nextCursor")
      end

      alias value result

      def notification
        Notification.new(@response)
      end

      def to_error
        Error.new(@error)
      end

      def raise_error!
        error = to_error
        message = "Response error: #{error}"
        raise Errors::ResponseError.new(message: message, error: error)
      end

      def matching_id?(request_id)
        @id == request_id
      end

      def next_cursor?
        !@next_cursor.nil?
      end

      def ping?
        @method == "ping"
      end

      def notification?
        @method.include?("notifications")
      end

      def success?
        !@result.empty?
      end

      def tool_success?
        success? && !@result_is_error
      end

      def error?
        !@error.empty?
      end
    end
  end
end
