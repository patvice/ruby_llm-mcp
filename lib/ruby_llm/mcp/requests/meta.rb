# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      module Meta
        def merge_meta(body)
          meta = {}
          meta.merge!(progress_token) if @coordinator.client.tracking_progress?

          if meta.empty?
            body
          else
            body.merge({ "_meta" => meta })
          end
        end

        private

        def progress_token
          { progressToken: generate_progress_token }
        end

        def generate_progress_token
          SecureRandom.hex(16)
        end
      end
    end
  end
end
