# frozen_string_literal: true

module RubyLLM
  module MCP
    class Notification
      attr_reader :type, :params

      def initialize(response)
        @type = response["method"]
        @params = response["params"]
      end
    end

    class Result
      attr_reader :result, :error, :params, :id, :next_cursor, :response

      def initialize(response)
        @response = response
        @id = response["id"]
        @method = response["method"]
        @result = response["result"] || {}
        @params = response["params"] || {}
        @error = response["error"] || {}

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

      def execution_error?
        @result_is_error
      end

      def raise_error!
        error = to_error
        message = "Response error: #{error}"
        raise Errors::ResponseError.new(message: message, error: error)
      end

      def matching_id?(request_id)
        @id&.to_s == request_id
      end

      def next_cursor?
        !@next_cursor.nil?
      end

      def ping?
        @method == "ping"
      end

      def notification?
        @method&.include?("notifications") || false
      end

      def request?
        @method && !notification? && @result.none? && @error.none?
      end

      def response?
        @id && (@result || @error.any?) && !@method
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

      def to_s
        inspect
      end

      def inspect
        "#<#{self.class.name}:0x#{object_id.to_s(16)} id: #{@id}, result: #{@result}, error: #{@error}, method: #{@method}, params: #{@params}>" # rubocop:disable Layout/LineLength
      end
    end
  end
end
