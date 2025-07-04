# frozen_string_literal: true

module RubyLLM
  module MCP
    module Transport
      module Timeout
        def with_timeout(seconds, request_id: nil)
          result = nil
          worker = Thread.new do
            result = yield
          end

          if worker.join(seconds)
            result
          else
            worker.kill # stop the thread (can still have some risk if shared resources)
            raise RubyLLM::MCP::Errors::TimeoutError.new(
              message: "Request timed out after #{@request_timeout / 1000} seconds",
              request_id: request_id
            )
          end
        end
      end
    end
  end
end
