# frozen_string_literal: true

module RubyLLM
  module MCP
    module Errors
      class BaseError < StandardError
        attr_reader :message

        def initialize(message:)
          @message = message
          super(message)
        end
      end

      module Capabilities
        class CompletionNotAvailable < BaseError; end
        class ResourceSubscribeNotAvailable < BaseError; end
      end

      class InvalidFormatError < BaseError; end

      class InvalidProtocolVersionError < BaseError; end

      class InvalidTransportType < BaseError; end

      class ProgressHandlerNotAvailable < BaseError; end

      class PromptArgumentError < BaseError; end

      class ResponseError < BaseError
        attr_reader :error

        def initialize(message:, error:)
          @error = error
          super(message: message)
        end
      end

      class SessionExpiredError < BaseError; end

      class TimeoutError < BaseError
        attr_reader :request_id

        def initialize(message:, request_id: nil)
          @request_id = request_id
          super(message: message)
        end
      end

      class TransportError < BaseError
        attr_reader :code, :error

        def initialize(message:, code: nil, error: nil)
          @code = code
          @error = error
          super(message: message)
        end
      end

      class UnknownRequest < BaseError; end

      class UnsupportedProtocolVersion < BaseError; end
    end
  end
end
