# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Responses
        class SamplingCreateMessage
          def initialize(coordinator, id:, message:, model:)
            @coordinator = coordinator
            @id = id
            @message = message
            @model = model
          end

          def call
            @coordinator.request(sampling_create_message_body, add_id: false, wait_for_response: false)
          end

          private

          def sampling_create_message_body
            {
              jsonrpc: "2.0",
              id: @id,
              result: {
                role: @message.role,
                content: format_content(@message.content),
                model: @model,
                # TODO: We are going to assume it was a endTurn
                # Look into getting RubyLLM to expose stopReason in message response
                stopReason: "endTurn"
              }
            }
          end

          def format_content(content)
            if content.is_a?(RubyLLM::Content)
              if content.text.none? && content.attachments.any?
                attachment = content.attachments.first
                { type: attachment.type, data: attachment.content, mime_type: attachment.mime_type }
              else
                { type: "text", text: content.text }
              end
            else
              { type: "text", text: content }
            end
          end
        end
      end
    end
  end
end
