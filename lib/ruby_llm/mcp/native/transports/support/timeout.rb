# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Transports
        module Support
          module Timeout
            def with_timeout(seconds, request_id: nil)
              result = nil
              exception = nil

              worker = Thread.new do
                result = yield
              rescue StandardError => e
                exception = e
              end

              if worker.join(seconds)
                raise exception if exception

                result
              else
                worker.kill # stop the thread (can still have some risk if shared resources)
                raise RubyLLM::MCP::Errors::TimeoutError.new(
                  message: "Request timed out after #{seconds} seconds",
                  request_id: request_id
                )
              end
            end
          end
        end
      end
    end
  end
end
