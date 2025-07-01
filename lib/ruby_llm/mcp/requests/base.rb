# frozen_string_literal: true

require "json"

module RubyLLM
  module MCP
    module Requests
      class Base
        attr_reader :coordinator

        def initialize(coordinator)
          @coordinator = coordinator
        end

        def call
          raise "Not implemented"
        end

        private

        def validate_response!(response, body)
          # TODO: Implement response validation
        end

        def raise_error(error)
          raise "MCP Error: code: #{error['code']} message: #{error['message']} data: #{error['data']}"
        end
      end
    end
  end
end
