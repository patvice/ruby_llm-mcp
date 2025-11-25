# frozen_string_literal: true

require "securerandom"

module RubyLLM
  module MCP
    module Native
      module Messages
        # Helper methods for message construction
        module Helpers
          def generate_id
            SecureRandom.uuid
          end

          def add_progress_token(params, tracking_progress: false)
            return params unless tracking_progress

            params[:_meta] ||= {}
            params[:_meta][:progressToken] = generate_id
            params
          end

          def add_cursor(params, cursor)
            return params unless cursor

            params[:cursor] = cursor
            params
          end

          def format_completion_context(context)
            return nil if context.nil?

            { arguments: context }
          end
        end
      end
    end
  end
end
