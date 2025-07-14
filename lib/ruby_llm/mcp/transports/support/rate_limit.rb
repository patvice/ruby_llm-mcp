# frozen_string_literal: true

module RubyLLM
  module MCP
    module Transports
      module Support
        class RateLimit
          def initialize(limit: 10, interval: 1000)
            @limit = limit
            @interval = interval
            @timestamps = []
            @mutex = Mutex.new
          end

          def exceeded?
            now = current_time

            @mutex.synchronize do
              purge_old(now)
              @timestamps.size >= @limit
            end
          end

          def add
            now = current_time

            @mutex.synchronize do
              purge_old(now)
              @timestamps << now
            end
          end

          private

          def current_time
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

          def purge_old(now)
            cutoff = now - @interval
            @timestamps.reject! { |t| t < cutoff }
          end
        end
      end
    end
  end
end
