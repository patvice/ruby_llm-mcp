# frozen_string_literal: true

require "securerandom"

module RubyLLM
  module MCP
    module Requests
      module Meta
        def merge_meta(body)
          meta = {}
          meta.merge!(progress_token) if @coordinator.client.tracking_progress?

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
