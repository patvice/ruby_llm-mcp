# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Requests
        module Shared
          module Meta
            def merge_meta(body)
              meta = {}
              meta.merge!(progress_token) if @coordinator.tracking_progress?

              body[:params] ||= {}
              body[:params].merge!({ _meta: meta }) unless meta.empty?
              body
            end

            private

            def progress_token
              { progressToken: generate_progress_token }
            end

            def generate_progress_token
              SecureRandom.uuid
            end
          end
        end
      end
    end
  end
end
